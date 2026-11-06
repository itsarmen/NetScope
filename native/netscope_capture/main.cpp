/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 *
 * netscope-capture.exe - realtime ETW capture helper.
 *
 * Subscribes to Microsoft-Windows-Kernel-Network (TCP/UDP + PID + bytes) and
 * Microsoft-Windows-DNS-Client (query/answers + PID), normalizes events to
 * NDJSON and streams them to the Flutter app over loopback TCP.
 *
 * The app passes --port/--token. If this process is not elevated it relaunches
 * itself through ShellExecuteEx("runas") and exits; the elevated instance
 * connects to the same port and verifies the token.
 */

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <shellapi.h>
#include <tdh.h>
#include <evntrace.h>
#include <evntcons.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <fstream>
#include <iterator>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace {

const GUID kKernelNetworkGuid = {
    0x7dd42a49, 0x5329, 0x4832,
    {0x8d, 0xfd, 0x43, 0xd9, 0x79, 0x15, 0x3a, 0x88}};
const GUID kDnsClientGuid = {
    0x1c95126e, 0x7eea, 0x49a9,
    {0xa3, 0xfe, 0xa3, 0x78, 0xb0, 0x3d, 0xdb, 0x4d}};

constexpr wchar_t kSessionName[] = L"NetScope-Etw";
constexpr ULONGLONG kIpv4Keywords = 0x10;
constexpr ULONGLONG kIpv6Keywords = 0x20;
constexpr ULONGLONG kAllKeywords = 0xFFFFFFFFFFFFFFFFULL;

struct Options {
  int port = 0;
  std::string token;
  bool stdoutMode = false;
  bool check = false;
  bool noElevate = false;
  bool help = false;
  std::wstring applyHostsSource;
  std::wstring applyHostsStatus;
};

std::string Narrow(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()),
                                       nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string out(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), out.data(), size,
                      nullptr, nullptr);
  return out;
}

std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()),
                                       nullptr, 0);
  if (size <= 0) return {};
  std::wstring out(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), out.data(), size);
  return out;
}

std::string JsonEscape(const std::string& value) {
  std::string out;
  out.reserve(value.size() + 8);
  for (unsigned char c : value) {
    switch (c) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      case '\b':
        out += "\\b";
        break;
      case '\f':
        out += "\\f";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        if (c < 0x20) {
          char buf[7];
          std::snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out.push_back(static_cast<char>(c));
        }
        break;
    }
  }
  return out;
}

std::string Timestamp(const EVENT_RECORD* record) {
  if (record == nullptr) return {};
  FILETIME ft;
  ft.dwLowDateTime =
      static_cast<DWORD>(record->EventHeader.TimeStamp.QuadPart & 0xFFFFFFFF);
  ft.dwHighDateTime =
      static_cast<DWORD>(record->EventHeader.TimeStamp.QuadPart >> 32);
  SYSTEMTIME st;
  if (!FileTimeToSystemTime(&ft, &st)) return {};
  char buf[40];
  std::snprintf(buf, sizeof(buf),
                "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ", st.wYear, st.wMonth,
                st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
  return buf;
}

std::string ToLower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return value;
}

std::string Trim(const std::string& value) {
  size_t start = 0;
  while (start < value.size() &&
         std::isspace(static_cast<unsigned char>(value[start]))) {
    ++start;
  }
  size_t end = value.size();
  while (end > start &&
         std::isspace(static_cast<unsigned char>(value[end - 1]))) {
    --end;
  }
  return value.substr(start, end - start);
}

std::vector<std::string> Split(const std::string& value, char delimiter) {
  std::vector<std::string> out;
  size_t start = 0;
  while (start <= value.size()) {
    const size_t pos = value.find(delimiter, start);
    if (pos == std::string::npos) {
      out.push_back(value.substr(start));
      break;
    }
    out.push_back(value.substr(start, pos - start));
    start = pos + 1;
  }
  return out;
}

bool IsLoopbackIp(const std::string& ip) {
  return ip == "::1" || ip.rfind("127.", 0) == 0;
}

std::string FormatIp(const BYTE* data, ULONG size) {
  if (data == nullptr) return {};
  char buf[INET6_ADDRSTRLEN] = {};
  if (size == 4) {
    if (inet_ntop(AF_INET, data, buf, sizeof(buf)) != nullptr) {
      return ToLower(buf);
    }
  } else if (size == 16) {
    if (inet_ntop(AF_INET6, data, buf, sizeof(buf)) != nullptr) {
      return ToLower(buf);
    }
  }
  return {};
}

std::string NormalizeAnswer(const std::string& raw) {
  std::string value = Trim(raw);
  if (value.empty()) return {};
  if (value.size() > 7 && value.rfind("::ffff:", 0) == 0) {
    value = value.substr(7);
  }
  unsigned char buf[16];
  if (value.find(':') != std::string::npos) {
    if (inet_pton(AF_INET6, value.c_str(), buf) == 1) return ToLower(value);
    return {};
  }
  if (inet_pton(AF_INET, value.c_str(), buf) == 1) return value;
  return {};
}

// ---------------------------------------------------------------------------
// Output sink
// ---------------------------------------------------------------------------

class Sink {
 public:
  bool ConnectTcp(int port, const std::string& token) {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return false;
    SOCKET socket = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (socket == INVALID_SOCKET) return false;

    sockaddr_in addr = {};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(static_cast<u_short>(port));
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
    if (::connect(socket, reinterpret_cast<sockaddr*>(&addr),
                  sizeof(addr)) == SOCKET_ERROR) {
      ::closesocket(socket);
      return false;
    }
    BOOL noDelay = TRUE;
    ::setsockopt(socket, IPPROTO_TCP, TCP_NODELAY,
                 reinterpret_cast<const char*>(&noDelay), sizeof(noDelay));

    sock_ = socket;
    SendLine("{\"kind\":\"hello\",\"token\":\"" + JsonEscape(token) + "\"}");
    return true;
  }

  void UseStdout() { stdout_ = true; }

  void SendLine(const std::string& line) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stdout_) {
      const std::string data = line + "\n";
      std::fwrite(data.data(), 1, data.size(), stdout);
      std::fflush(stdout);
      return;
    }
    if (sock_ == INVALID_SOCKET) return;
    const std::string data = line + "\n";
    size_t offset = 0;
    while (offset < data.size()) {
      const int sent =
          ::send(sock_, data.data() + offset,
                 static_cast<int>(data.size() - offset), 0);
      if (sent <= 0) {
        ::closesocket(sock_);
        sock_ = INVALID_SOCKET;
        return;
      }
      offset += static_cast<size_t>(sent);
    }
  }

  void Close() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (sock_ != INVALID_SOCKET) {
      ::shutdown(sock_, SD_BOTH);
      ::closesocket(sock_);
      sock_ = INVALID_SOCKET;
    }
    if (stdout_) {
      std::fflush(stdout);
    }
  }

  SOCKET socket() const { return sock_; }

 private:
  SOCKET sock_ = INVALID_SOCKET;
  bool stdout_ = false;
  std::mutex mutex_;
};

Sink* g_sink = nullptr;
std::atomic<bool> g_stopping{false};
std::atomic<uint64_t> g_sequence{0};

// ---------------------------------------------------------------------------
// Process name cache
// ---------------------------------------------------------------------------

struct ProcessInfo {
  std::string name;
  std::string path;
};

std::unordered_map<uint32_t, ProcessInfo> g_processCache;

ProcessInfo GetProcessInfo(uint32_t pid) {
  if (pid == 0) return {"System Idle", ""};
  if (pid == 4) return {"System", ""};

  const auto cached = g_processCache.find(pid);
  if (cached != g_processCache.end()) return cached->second;

  ProcessInfo info;
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process != nullptr) {
    wchar_t path[MAX_PATH];
    DWORD size = static_cast<DWORD>(std::size(path));
    if (QueryFullProcessImageNameW(process, 0, path, &size)) {
      const std::wstring full(path, size);
      info.path = Narrow(full);
      const size_t slash = full.find_last_of(L"\\/");
      info.name = Narrow(slash == std::wstring::npos
                             ? full
                             : full.substr(slash + 1));
    }
    CloseHandle(process);
  }
  g_processCache[pid] = info;
  return info;
}

// ---------------------------------------------------------------------------
// TDH property helpers
// ---------------------------------------------------------------------------

bool GetPropertyBytes(EVENT_RECORD* record, const wchar_t* name,
                      std::vector<BYTE>& out) {
  if (record == nullptr || name == nullptr) return false;
  PROPERTY_DATA_DESCRIPTOR descriptor = {};
  descriptor.PropertyName = reinterpret_cast<ULONGLONG>(name);
  descriptor.ArrayIndex = ULONG_MAX;

  ULONG size = 0;
  if (TdhGetPropertySize(record, 0, nullptr, 1, &descriptor, &size) !=
      ERROR_SUCCESS) {
    return false;
  }
  out.resize(size);
  if (size == 0) return true;
  return TdhGetProperty(record, 0, nullptr, 1, &descriptor, size,
                        out.data()) == ERROR_SUCCESS;
}

bool GetU32(EVENT_RECORD* record, const wchar_t* name, uint32_t& value) {
  std::vector<BYTE> bytes;
  if (!GetPropertyBytes(record, name, bytes) || bytes.size() < 4) return false;
  std::memcpy(&value, bytes.data(), 4);
  return true;
}

bool GetU16(EVENT_RECORD* record, const wchar_t* name, uint16_t& value) {
  std::vector<BYTE> bytes;
  if (!GetPropertyBytes(record, name, bytes) || bytes.size() < 2) return false;
  uint16_t raw = 0;
  std::memcpy(&raw, bytes.data(), 2);
  // Kernel-Network stores dport/sport in network byte order.
  value = ntohs(raw);
  return true;
}

bool GetString(EVENT_RECORD* record, const wchar_t* name, std::string& value) {
  std::vector<BYTE> bytes;
  if (!GetPropertyBytes(record, name, bytes) || bytes.size() < 2) return false;
  const size_t chars = bytes.size() / sizeof(wchar_t);
  const wchar_t* text = reinterpret_cast<const wchar_t*>(bytes.data());
  size_t length = chars;
  while (length > 0 && text[length - 1] == L'\0') --length;
  value = Narrow(std::wstring(text, length));
  return true;
}

// ---------------------------------------------------------------------------
// Event handling
// ---------------------------------------------------------------------------

std::unordered_map<std::string, std::string> g_ipDomains;
std::unordered_map<std::string, ULONGLONG> g_udpSeen;

void HandleDns(EVENT_RECORD* record, Sink& sink) {
  if (record == nullptr) return;
  if (record->EventHeader.EventDescriptor.Id != 3008) return;

  std::string query;
  if (!GetString(record, L"QueryName", query)) return;
  query = Trim(query);
  if (query.empty()) return;

  std::string results;
  GetString(record, L"QueryResults", results);

  uint32_t status = 0;
  GetU32(record, L"QueryStatus", status);

  std::vector<std::string> answers;
  for (const std::string& part : Split(results, ';')) {
    const std::string answer = NormalizeAnswer(part);
    if (answer.empty()) continue;
    answers.push_back(answer);
    if (g_ipDomains.size() < 20000) {
      g_ipDomains[answer] = query;
    }
  }

  const uint32_t pid = record->EventHeader.ProcessId;
  const ProcessInfo process = GetProcessInfo(pid);
  const std::string timestamp = Timestamp(record);
  const std::string id =
      "dns-" + std::to_string(++g_sequence) + "-" + std::to_string(pid);

  std::ostringstream line;
  line << "{\"kind\":\"dns\""
       << ",\"id\":\"" << JsonEscape(id) << "\""
       << ",\"ts\":\"" << JsonEscape(timestamp) << "\""
       << ",\"pid\":" << pid
       << ",\"process\":\"" << JsonEscape(process.name) << "\""
       << ",\"processPath\":\"" << JsonEscape(process.path) << "\""
       << ",\"query\":\"" << JsonEscape(query) << "\""
       << ",\"status\":\"" << (status == 0 ? "Success" : "Failed") << "\""
       << ",\"answers\":[";
  for (size_t i = 0; i < answers.size(); ++i) {
    if (i != 0) line << ',';
    line << '"' << JsonEscape(answers[i]) << '"';
  }
  line << "]";
  if (!answers.empty()) {
    line << ",\"remoteIp\":\"" << JsonEscape(answers.front()) << "\"";
  }
  line << '}';
  sink.SendLine(line.str());
}

void HandleKernel(EVENT_RECORD* record, Sink& sink) {
  if (record == nullptr) return;

  enum class Kind { ignore, connect, accept, udpSend, udpRecv };
  Kind kind = Kind::ignore;
  bool udp = false;

  switch (record->EventHeader.EventDescriptor.Id) {
    case 12:
    case 16:
    case 28:
    case 32:
      kind = Kind::connect;
      break;
    case 15:
    case 31:
      kind = Kind::accept;
      break;
    case 42:
    case 58:
      kind = Kind::udpSend;
      udp = true;
      break;
    case 43:
    case 59:
      kind = Kind::udpRecv;
      udp = true;
      break;
    default:
      return;
  }

  uint32_t pid = 0;
  if (!GetU32(record, L"PID", pid) || pid == 0) {
    pid = record->EventHeader.ProcessId;
  }
  if (pid == 0) return;

  const ProcessInfo process = GetProcessInfo(pid);
  if (process.name == "netscope-capture.exe" ||
      process.name == "netscope.exe") {
    return;
  }

  std::vector<BYTE> daddr;
  std::vector<BYTE> saddr;
  if (!GetPropertyBytes(record, L"daddr", daddr) ||
      !GetPropertyBytes(record, L"saddr", saddr)) {
    return;
  }

  uint16_t dport = 0;
  uint16_t sport = 0;
  GetU16(record, L"dport", dport);
  GetU16(record, L"sport", sport);

  const std::string destination = FormatIp(daddr.data(),
                                           static_cast<ULONG>(daddr.size()));
  const std::string source = FormatIp(saddr.data(),
                                      static_cast<ULONG>(saddr.size()));
  if (destination.empty() || source.empty()) return;

  std::string localIp;
  std::string remoteIp;
  uint16_t localPort = 0;
  uint16_t remotePort = 0;
  std::string direction;

  if (kind == Kind::connect || kind == Kind::udpSend) {
    // Connect/UDP send: source is local, destination is remote.
    localIp = source;
    localPort = sport;
    remoteIp = destination;
    remotePort = dport;
    direction = "outbound";
  } else if (kind == Kind::accept) {
    // Accept: source is the local server, destination is the remote client.
    localIp = source;
    localPort = sport;
    remoteIp = destination;
    remotePort = dport;
    direction = "inbound";
  } else {
    // UDP receive: source is remote, destination is local.
    localIp = destination;
    localPort = dport;
    remoteIp = source;
    remotePort = sport;
    direction = "inbound";
  }

  if (IsLoopbackIp(remoteIp) && IsLoopbackIp(localIp)) {
    direction = "loopback";
  }

  const std::string key = std::string(udp ? "udp|" : "tcp|") +
                          std::to_string(pid) + "|" + localIp + ":" +
                          std::to_string(localPort) + "|" + remoteIp + ":" +
                          std::to_string(remotePort);

  if (udp) {
    const ULONGLONG now = GetTickCount64();
    const auto found = g_udpSeen.find(key);
    if (found != g_udpSeen.end() && now - found->second < 10000) return;
    if (g_udpSeen.size() > 10000) g_udpSeen.clear();
    g_udpSeen[key] = now;
  }

  uint32_t size = 0;
  GetU32(record, L"size", size);

  std::string domain;
  const auto mapped = g_ipDomains.find(remoteIp);
  if (mapped != g_ipDomains.end()) domain = mapped->second;

  const std::string state =
      udp ? "udp" : (kind == Kind::connect ? "attempted" : "established");
  const std::string protocol = udp ? "udp" : "tcp";
  const std::string timestamp = Timestamp(record);
  const std::string id = key + "|" + std::to_string(++g_sequence);

  const uint32_t bytesSent =
      (udp && kind == Kind::udpSend) ? size : 0;
  const uint32_t bytesReceived =
      (udp && kind == Kind::udpRecv) ? size : 0;

  std::ostringstream line;
  line << "{\"kind\":\"flow\""
       << ",\"id\":\"" << JsonEscape(id) << "\""
       << ",\"ts\":\"" << JsonEscape(timestamp) << "\""
       << ",\"direction\":\"" << direction << "\""
       << ",\"pid\":" << pid
       << ",\"process\":\"" << JsonEscape(process.name) << "\""
       << ",\"processPath\":\"" << JsonEscape(process.path) << "\""
       << ",\"protocol\":\"" << protocol << "\""
       << ",\"state\":\"" << state << "\""
       << ",\"localIp\":\"" << JsonEscape(localIp) << "\""
       << ",\"localPort\":" << localPort
       << ",\"remoteIp\":\"" << JsonEscape(remoteIp) << "\""
       << ",\"remotePort\":" << remotePort
       << ",\"domain\":\"" << JsonEscape(domain) << "\""
       << ",\"bytesSent\":" << bytesSent
       << ",\"bytesReceived\":" << bytesReceived
       << '}';
  sink.SendLine(line.str());
}

void WINAPI OnEvent(PEVENT_RECORD record) {
  if (record == nullptr || g_sink == nullptr) return;
  if (IsEqualGUID(record->EventHeader.ProviderId, kKernelNetworkGuid)) {
    HandleKernel(record, *g_sink);
  } else if (IsEqualGUID(record->EventHeader.ProviderId, kDnsClientGuid)) {
    HandleDns(record, *g_sink);
  }
}

// ---------------------------------------------------------------------------
// Session management
// ---------------------------------------------------------------------------

TRACEHANDLE g_session = 0;

void StopSession() {
  if (g_stopping.exchange(true)) return;
  const size_t nameBytes = std::size(kSessionName) * sizeof(wchar_t);
  std::vector<BYTE> buffer(sizeof(EVENT_TRACE_PROPERTIES) + nameBytes, 0);
  auto* properties = reinterpret_cast<EVENT_TRACE_PROPERTIES*>(buffer.data());
  properties->Wnode.BufferSize = static_cast<ULONG>(buffer.size());
  properties->LoggerNameOffset = sizeof(EVENT_TRACE_PROPERTIES);
  ControlTraceW(0, kSessionName, properties, EVENT_TRACE_CONTROL_STOP);
}

BOOL WINAPI ConsoleHandler(DWORD) {
  StopSession();
  return TRUE;
}

ULONG StartSession() {
  const size_t nameBytes = (std::size(kSessionName)) * sizeof(wchar_t);
  std::vector<BYTE> buffer(sizeof(EVENT_TRACE_PROPERTIES) + nameBytes, 0);
  auto* properties = reinterpret_cast<EVENT_TRACE_PROPERTIES*>(buffer.data());

  auto initialize = [&]() {
    std::memset(buffer.data(), 0, buffer.size());
    properties->Wnode.BufferSize = static_cast<ULONG>(buffer.size());
    properties->Wnode.Flags = WNODE_FLAG_TRACED_GUID;
    properties->Wnode.ClientContext = 1;
    properties->LogFileMode = EVENT_TRACE_REAL_TIME_MODE;
    properties->FlushTimer = 1;
    properties->LoggerNameOffset = sizeof(EVENT_TRACE_PROPERTIES);
    properties->LogFileNameOffset = 0;
  };

  initialize();
  ULONG result = StartTraceW(&g_session, kSessionName, properties);
  if (result == ERROR_ALREADY_EXISTS) {
    ControlTraceW(0, kSessionName, properties, EVENT_TRACE_CONTROL_STOP);
    initialize();
    result = StartTraceW(&g_session, kSessionName, properties);
  }
  return result;
}

void Log(const std::string& message) {
  std::fprintf(stderr, "%s\n", message.c_str());
  wchar_t temp[MAX_PATH];
  const DWORD length = GetTempPathW(static_cast<DWORD>(std::size(temp)), temp);
  if (length > 0 && length < std::size(temp)) {
    std::wstring path(temp, length);
    path += L"netscope-capture.log";
    std::ofstream file(path.c_str(), std::ios::app);
    if (file) {
      SYSTEMTIME st;
      GetLocalTime(&st);
      file << st.wYear << '-' << st.wMonth << '-' << st.wDay << ' '
           << st.wHour << ':' << st.wMinute << ':' << st.wSecond << "  "
           << message << "\n";
    }
  }
}

bool IsElevated() {
  BOOL isAdmin = FALSE;
  PSID administrators = nullptr;
  SID_IDENTIFIER_AUTHORITY authority = SECURITY_NT_AUTHORITY;
  if (AllocateAndInitializeSid(&authority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                               DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0,
                               &administrators)) {
    CheckTokenMembership(nullptr, administrators, &isAdmin);
    FreeSid(administrators);
  }
  return isAdmin != FALSE;
}

std::wstring QuoteArgument(const std::wstring& value) {
  if (value.find_first_of(L" \t\"") == std::wstring::npos) return value;
  std::wstring out = L"\"";
  for (wchar_t c : value) {
    if (c == L'"') out += L'\\';
    out += c;
  }
  out += L'"';
  return out;
}

bool RelaunchElevated(int argc, wchar_t** argv) {
  wchar_t module[MAX_PATH];
  const DWORD length =
      GetModuleFileNameW(nullptr, module, static_cast<DWORD>(std::size(module)));
  if (length == 0 || length >= std::size(module)) return false;

  std::wstring parameters;
  for (int i = 1; i < argc; ++i) {
    if (!parameters.empty()) parameters += L' ';
    parameters += QuoteArgument(argv[i]);
  }

  SHELLEXECUTEINFOW execute = {};
  execute.cbSize = sizeof(execute);
  execute.fMask = SEE_MASK_NOCLOSEPROCESS;
  execute.lpVerb = L"runas";
  execute.lpFile = module;
  execute.lpParameters = parameters.c_str();
  execute.nShow = SW_HIDE;

  if (!ShellExecuteExW(&execute)) {
    Log("Elevation was cancelled or failed (error " +
        std::to_string(GetLastError()) + ")");
    return false;
  }
  if (execute.hProcess != nullptr) CloseHandle(execute.hProcess);
  return true;
}

Options ParseOptions(int argc, wchar_t** argv) {
  Options options;
  for (int i = 1; i < argc; ++i) {
    const std::wstring arg = argv[i];
    if (arg == L"--port" && i + 1 < argc) {
      options.port = static_cast<int>(wcstol(argv[++i], nullptr, 10));
    } else if (arg == L"--token" && i + 1 < argc) {
      options.token = Narrow(argv[++i]);
    } else if (arg == L"--apply-hosts" && i + 1 < argc) {
      options.applyHostsSource = argv[++i];
    } else if (arg == L"--status" && i + 1 < argc) {
      options.applyHostsStatus = argv[++i];
    } else if (arg == L"--stdout") {
      options.stdoutMode = true;
    } else if (arg == L"--check") {
      options.check = true;
    } else if (arg == L"--no-elevate") {
      options.noElevate = true;
    } else if (arg == L"--help" || arg == L"-h" || arg == L"/?") {
      options.help = true;
    }
  }
  return options;
}

void PrintHelp() {
  std::printf(
      "netscope-capture.exe - NetScope ETW helper\n"
      "\n"
      "Usage:\n"
      "  netscope-capture.exe --port <port> --token <token>\n"
      "  netscope-capture.exe --apply-hosts <file> [--status <file>]\n"
      "  netscope-capture.exe --stdout\n"
      "  netscope-capture.exe --check\n"
      "\n"
      "The app launches the helper with --port/--token. The helper elevates\n"
      "itself (UAC) and streams NDJSON to 127.0.0.1:<port>.\n"
      "\n"
      "Options:\n"
      "  --port <n>            Loopback TCP port opened by the app\n"
      "  --token <s>           Shared token sent in the hello line\n"
      "  --apply-hosts <file>  Replace the Windows hosts file with <file>\n"
      "  --status <file>       Write a JSON result for --apply-hosts\n"
      "  --stdout              Write NDJSON to stdout (run elevated manually)\n"
      "  --check               Print elevation status and exit\n"
      "  --no-elevate          Do not trigger UAC (testing)\n"
      "  --help                Show this help\n");
}

// ---------------------------------------------------------------------------
// Hosts file writer (used by the GUI hosts editor)
// ---------------------------------------------------------------------------

std::wstring HostsFilePath() {
  wchar_t windows[MAX_PATH];
  const UINT length =
      GetWindowsDirectoryW(windows, static_cast<UINT>(std::size(windows)));
  std::wstring root = length > 0 ? std::wstring(windows, length) : L"C:\\Windows";
  return root + L"\\System32\\drivers\\etc\\hosts";
}

void WriteHostsStatus(const std::wstring& path, bool ok,
                      const std::string& message) {
  if (path.empty()) return;
  std::ofstream file(path.c_str(), std::ios::binary | std::ios::trunc);
  if (!file) return;
  file << "{\"ok\":" << (ok ? "true" : "false")
       << ",\"message\":\"" << JsonEscape(message) << "\"}";
  file.flush();
}

int ApplyHostsFile(const std::wstring& sourcePath,
                   const std::wstring& statusPath) {
  auto fail = [&](const std::string& message) {
    WriteHostsStatus(statusPath, false, message);
    Log(message);
    return 1;
  };

  std::ifstream input(sourcePath.c_str(), std::ios::binary);
  if (!input) return fail("Could not read the pending hosts file.");
  std::string content((std::istreambuf_iterator<char>(input)),
                      std::istreambuf_iterator<char>());
  if (content.size() > 1024 * 1024) {
    return fail("The pending hosts file is too large.");
  }
  if (content.find('\0') != std::string::npos) {
    return fail("The pending hosts file contains invalid data.");
  }

  const std::wstring target = HostsFilePath();
  const std::wstring backup = target + L".netscope.bak";
  if (!CopyFileW(target.c_str(), backup.c_str(), FALSE)) {
    const DWORD error = GetLastError();
    if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) {
      Log("Could not back up the hosts file (error " +
          std::to_string(error) + ")");
    }
  }

  const std::wstring temp = target + L".netscope.tmp";
  HANDLE file = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return fail("Could not open a temporary hosts file.");
  }

  DWORD written = 0;
  const BOOL ok =
      WriteFile(file, content.data(), static_cast<DWORD>(content.size()),
                &written, nullptr);
  FlushFileBuffers(file);
  CloseHandle(file);
  if (!ok || written != content.size()) {
    DeleteFileW(temp.c_str());
    return fail("Could not write the hosts file.");
  }

  if (!MoveFileExW(temp.c_str(), target.c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    if (!CopyFileW(temp.c_str(), target.c_str(), FALSE)) {
      DeleteFileW(temp.c_str());
      return fail("Could not replace the hosts file.");
    }
    DeleteFileW(temp.c_str());
  }

  HMODULE dnsapi = LoadLibraryW(L"dnsapi.dll");
  if (dnsapi != nullptr) {
    using FlushDnsCacheFn = BOOL(WINAPI*)();
    auto flush = reinterpret_cast<FlushDnsCacheFn>(
        GetProcAddress(dnsapi, "DnsFlushResolverCache"));
    if (flush != nullptr) flush();
    FreeLibrary(dnsapi);
  }
  WriteHostsStatus(statusPath, true,
                   "Hosts file updated and DNS cache flushed.");
  return 0;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  // The helper is a GUI-subsystem process so the app never flashes a console.
  // When run from a terminal, attach to that console for --check/--stdout,
  // but keep redirected pipes/files intact for automated diagnostics.
  if (AttachConsole(ATTACH_PARENT_PROCESS)) {
    auto attach_stream = [](DWORD which, FILE* stream) {
      HANDLE handle = GetStdHandle(which);
      if (handle == nullptr || handle == INVALID_HANDLE_VALUE) {
        FILE* reopened = nullptr;
        freopen_s(&reopened, "CONOUT$", "w", stream);
      }
    };
    attach_stream(STD_OUTPUT_HANDLE, stdout);
    attach_stream(STD_ERROR_HANDLE, stderr);
  }

  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) return 1;

  const Options options = ParseOptions(argc, argv);
  LocalFree(argv);

  if (options.help) {
    PrintHelp();
    return 0;
  }

  const bool elevated = IsElevated();
  if (options.check) {
    std::printf("{\"elevated\":%s,\"session\":\"%s\"}\n",
                elevated ? "true" : "false", "NetScope-Etw");
    return 0;
  }

  auto relaunchElevated = []() -> int {
    // Rebuild the original argv for the elevated instance.
    int relaunchArgc = 0;
    wchar_t** relaunchArgv =
        CommandLineToArgvW(GetCommandLineW(), &relaunchArgc);
    if (relaunchArgv == nullptr) return 2;
    const bool launched = RelaunchElevated(relaunchArgc, relaunchArgv);
    LocalFree(relaunchArgv);
    return launched ? 0 : 2;
  };

  if (!elevated) {
    if (options.noElevate) {
      Log("Administrator rights are required for this operation.");
      return 2;
    }
    if (!options.applyHostsSource.empty() || options.port > 0) {
      return relaunchElevated();
    }
    Log("Run this helper from an elevated console for --stdout mode.");
    return 2;
  }

  if (!options.applyHostsSource.empty()) {
    return ApplyHostsFile(options.applyHostsSource, options.applyHostsStatus);
  }

  Sink sink;
  if (options.port > 0) {
    if (!sink.ConnectTcp(options.port, options.token)) {
      Log("Could not connect to the NetScope app on 127.0.0.1:" +
          std::to_string(options.port));
      return 3;
    }
  } else {
    sink.UseStdout();
  }
  g_sink = &sink;

  if (sink.socket() != INVALID_SOCKET) {
    const SOCKET socket = sink.socket();
    std::thread([socket]() {
      char buffer[256];
      for (;;) {
        const int received = ::recv(socket, buffer, sizeof(buffer), 0);
        if (received <= 0) break;
      }
      StopSession();
    }).detach();
  } else {
    SetConsoleCtrlHandler(ConsoleHandler, TRUE);
  }

  const ULONG startResult = StartSession();
  if (startResult != ERROR_SUCCESS) {
    Log("StartTrace failed with error " + std::to_string(startResult) +
        ". Is another capture session running?");
    sink.Close();
    return 4;
  }

  const ULONG kernelResult = EnableTraceEx2(
      g_session, &kKernelNetworkGuid, EVENT_CONTROL_CODE_ENABLE_PROVIDER,
      TRACE_LEVEL_VERBOSE, kIpv4Keywords | kIpv6Keywords, 0, 0, nullptr);
  if (kernelResult != ERROR_SUCCESS) {
    Log("Could not enable Kernel-Network provider: " +
        std::to_string(kernelResult));
  }

  const ULONG dnsResult = EnableTraceEx2(
      g_session, &kDnsClientGuid, EVENT_CONTROL_CODE_ENABLE_PROVIDER,
      TRACE_LEVEL_VERBOSE, kAllKeywords, 0, 0, nullptr);
  if (dnsResult != ERROR_SUCCESS) {
    Log("Could not enable DNS-Client provider: " +
        std::to_string(dnsResult));
  }

  if (kernelResult != ERROR_SUCCESS && dnsResult != ERROR_SUCCESS) {
    Log("No ETW providers could be enabled; giving up.");
    StopSession();
    sink.Close();
    return 5;
  }

  EVENT_TRACE_LOGFILEW logFile = {};
  logFile.LoggerName = const_cast<LPWSTR>(kSessionName);
  logFile.ProcessTraceMode =
      PROCESS_TRACE_MODE_REAL_TIME | PROCESS_TRACE_MODE_EVENT_RECORD;
  logFile.EventRecordCallback = OnEvent;

  TRACEHANDLE trace = OpenTraceW(&logFile);
  if (trace == INVALID_PROCESSTRACE_HANDLE) {
    Log("OpenTrace failed with error " + std::to_string(GetLastError()));
    StopSession();
    sink.Close();
    return 6;
  }

  const ULONG processResult = ProcessTrace(&trace, 1, nullptr, nullptr);
  if (processResult != ERROR_SUCCESS && processResult != ERROR_CANCELLED) {
    Log("ProcessTrace returned " + std::to_string(processResult));
  }

  CloseTrace(trace);
  StopSession();
  sink.Close();
  return 0;
}
