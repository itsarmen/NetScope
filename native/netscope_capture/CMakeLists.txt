# Native ETW capture helper for NetScope.
#
# The Flutter app launches it with --port/--token and talks over loopback TCP.
# It is still usable manually from a terminal:
#   netscope-capture.exe --check
#   netscope-capture.exe --stdout

# WIN32 => GUI subsystem, so spawning it from the Flutter GUI does not create
# a console window. It attaches to an existing console for --check/--stdout.
add_executable(netscope_capture WIN32 main.cpp)
set_target_properties(netscope_capture PROPERTIES OUTPUT_NAME "netscope-capture")

target_compile_features(netscope_capture PRIVATE cxx_std_17)
target_compile_definitions(netscope_capture PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(netscope_capture PRIVATE /W4 /EHsc)
target_link_libraries(netscope_capture PRIVATE
  tdh
  advapi32
  ole32
  shell32
  ws2_32
)
