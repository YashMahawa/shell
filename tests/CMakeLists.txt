find_package(Qt6 REQUIRED COMPONENTS Core Qml)

add_executable(test_inputconfig
    test_inputconfig.cpp
)

set_target_properties(test_inputconfig PROPERTIES AUTOMOC ON)

target_include_directories(test_inputconfig PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../plugin/src/Caelestia/Config
)

target_link_libraries(test_inputconfig PRIVATE
    caelestia-config
    Qt6::Core
    Qt6::Qml
)

add_test(NAME test_inputconfig COMMAND test_inputconfig)
