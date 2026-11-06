/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

/// Bundled demonstration blocklist. Real feeds (abuse.ch, StevenBlack, ...)
/// can be loaded into the database and merged here in a later phase.
///
/// Entries use reserved test domains / TEST-NET ranges so the defaults never
/// point at a real third party.
const Set<String> kBundledBlockedDomains = {
  'malware.test',
  'c2.example',
  'phishing.example',
  'beacon.example',
};

const Set<String> kBundledBlockedIps = {
  '203.0.113.66',
  '198.51.100.23',
  '192.0.2.44',
};

bool isBlockedDomain(String domain) {
  if (domain.isEmpty) return false;
  final d = domain.toLowerCase();
  for (final blocked in kBundledBlockedDomains) {
    if (d == blocked || d.endsWith('.$blocked')) return true;
  }
  return false;
}

bool isBlockedIp(String ip) => kBundledBlockedIps.contains(ip);
