# =============================================================================
#  cmake-flash-kit :: FlashKit.cmake
#  可选模块：把烧录能力暴露成 CMake target，方便 CLion / 命令行使用。
#
#  用法（放在 add_executable 之后）：
#      include(${CMAKE_CURRENT_LIST_DIR}/.flash/cmake/FlashKit.cmake)
#  之后：
#      cmake --build build --target flash          # 编译 + 自动烧录
#      cmake --build build --target flash-stlink   # 强制 ST-Link
#      cmake --build build --target flash-daplink  # 强制 DAPLink
# =============================================================================

if(NOT DEFINED FLASHKIT_SCRIPT)
    set(FLASHKIT_SCRIPT "${CMAKE_CURRENT_LIST_DIR}/../flash.ps1")
    get_filename_component(FLASHKIT_SCRIPT "${FLASHKIT_SCRIPT}" ABSOLUTE)
endif()

if(NOT EXISTS "${FLASHKIT_SCRIPT}")
    message(WARNING "cmake-flash-kit: 找不到 ${FLASHKIT_SCRIPT}，flash target 不会生效")
    return()
endif()

find_program(FLASHKIT_POWERSHELL NAMES pwsh powershell)

if(NOT FLASHKIT_POWERSHELL)
    message(WARNING "cmake-flash-kit: 没有找到 PowerShell，flash target 不会生效")
    return()
endif()

# 默认依赖与本工程同名的可执行目标（CubeMX 生成的工程通常就是 ${PROJECT_NAME}）
if(NOT DEFINED FLASHKIT_TARGET AND TARGET ${PROJECT_NAME})
    set(FLASHKIT_TARGET ${PROJECT_NAME})
endif()

set(FLASHKIT_BASE_CMD
    "${FLASHKIT_POWERSHELL}" -NoProfile -ExecutionPolicy Bypass -File "${FLASHKIT_SCRIPT}"
)

if(FLASHKIT_TARGET)
    add_custom_target(flash
        COMMAND ${FLASHKIT_BASE_CMD}
        DEPENDS ${FLASHKIT_TARGET}
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        USES_TERMINAL
        COMMENT "cmake-flash-kit: 编译并烧录")
else()
    add_custom_target(flash
        COMMAND ${FLASHKIT_BASE_CMD}
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        USES_TERMINAL
        COMMENT "cmake-flash-kit: 编译并烧录")
endif()

add_custom_target(flash-stlink
    COMMAND ${FLASHKIT_BASE_CMD} -Probe stlink
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    USES_TERMINAL
    COMMENT "cmake-flash-kit: 使用 ST-Link 烧录")

add_custom_target(flash-daplink
    COMMAND ${FLASHKIT_BASE_CMD} -Probe daplink
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    USES_TERMINAL
    COMMENT "cmake-flash-kit: 使用 DAPLink 烧录")

add_custom_target(flash-list
    COMMAND ${FLASHKIT_BASE_CMD} -ListProbes
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    USES_TERMINAL
    COMMENT "cmake-flash-kit: 列出已连接的下载器")
