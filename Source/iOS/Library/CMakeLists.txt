add_library(dolphin SHARED
  Host.mm
  HostQueue.h
  HostQueue.mm
)

set_target_properties(dolphin PROPERTIES
  LINK_FLAGS "-Wl,-all_load,-undefined,dynamic_lookup"
)

target_link_libraries(dolphin
PUBLIC
  common
  core
  uicommon
)

target_link_libraries(dolphin
PRIVATE
${COCOA_TOUCH_LIBRARY}
${OPENGL_LIBRARY}
)
