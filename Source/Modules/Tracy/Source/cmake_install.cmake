# Install script for directory: /home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/usr/local")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Install shared libraries without execute permission?
if(NOT DEFINED CMAKE_INSTALL_SO_NO_EXE)
  set(CMAKE_INSTALL_SO_NO_EXE "1")
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "FALSE")
endif()

# Set default install directory permissions.
if(NOT DEFINED CMAKE_OBJDUMP)
  set(CMAKE_OBJDUMP "/usr/bin/objdump")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "lib" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/" TYPE STATIC_LIBRARY FILES "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/libTracyClient.a")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/tracy/tracy" TYPE FILE FILES
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/tracy/TracyC.h"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/tracy/Tracy.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/tracy/TracyCUDA.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/tracy/TracyD3D11.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/tracy/TracyD3D12.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/tracy/TracyLua.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/tracy/TracyMetal.hmm"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/tracy/TracyOpenCL.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/tracy/TracyOpenGL.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/tracy/TracyVulkan.hpp"
    )
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/tracy/client" TYPE FILE FILES
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/tracy_concurrentqueue.h"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/tracy_rpmalloc.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/tracy_SPSCQueue.h"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyKCore.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyArmCpuTable.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyCallstack.h"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyCallstack.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyCpuid.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyDebug.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyDxt1.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyFastVector.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyLock.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyProfiler.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyRingBuffer.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyScoped.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyStringHelpers.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracySysPower.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracySysTime.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracySysTrace.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/client/TracyThread.hpp"
    )
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/tracy/common" TYPE FILE FILES
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/tracy_lz4.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/tracy_lz4hc.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyAlign.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyAlloc.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyApi.h"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyColor.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyForceInline.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyMutex.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyProtocol.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyQueue.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracySocket.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyStackFrames.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracySystem.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyWinFamily.hpp"
    "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/public/common/TracyYield.hpp"
    )
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  if(EXISTS "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/Tracy/TracyTargets.cmake")
    file(DIFFERENT _cmake_export_file_changed FILES
         "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/Tracy/TracyTargets.cmake"
         "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/CMakeFiles/Export/b11871b887d9a65b4500cc2803d48638/TracyTargets.cmake")
    if(_cmake_export_file_changed)
      file(GLOB _cmake_old_config_files "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/Tracy/TracyTargets-*.cmake")
      if(_cmake_old_config_files)
        string(REPLACE ";" ", " _cmake_old_config_files_text "${_cmake_old_config_files}")
        message(STATUS "Old export file \"$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/Tracy/TracyTargets.cmake\" will be replaced.  Removing files [${_cmake_old_config_files_text}].")
        unset(_cmake_old_config_files_text)
        file(REMOVE ${_cmake_old_config_files})
      endif()
      unset(_cmake_old_config_files)
    endif()
    unset(_cmake_export_file_changed)
  endif()
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/Tracy" TYPE FILE FILES "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/CMakeFiles/Export/b11871b887d9a65b4500cc2803d48638/TracyTargets.cmake")
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^()$")
    file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/Tracy" TYPE FILE FILES "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/CMakeFiles/Export/b11871b887d9a65b4500cc2803d48638/TracyTargets-noconfig.cmake")
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/Tracy" TYPE FILE FILES "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/TracyConfig.cmake")
endif()

if(CMAKE_INSTALL_COMPONENT)
  set(CMAKE_INSTALL_MANIFEST "install_manifest_${CMAKE_INSTALL_COMPONENT}.txt")
else()
  set(CMAKE_INSTALL_MANIFEST "install_manifest.txt")
endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
file(WRITE "/home/stefan/Desktop/Yet-Another-Language/Source/Modules/Tracy/Source/${CMAKE_INSTALL_MANIFEST}"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
