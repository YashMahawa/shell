find_package(Qt6 REQUIRED COMPONENTS Test DBus Core Qml Quick)

enable_testing()

add_executable(test_bluetoothagent test_bluetoothagent.cpp)
target_link_libraries(test_bluetoothagent PRIVATE
    caelestia-services
    Qt6::Test
    Qt6::DBus
    Qt6::Core
    Qt6::Qml
    Qt6::Quick
)
target_include_directories(test_bluetoothagent PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src/Caelestia)

add_test(NAME test_bluetoothagent COMMAND test_bluetoothagent)
set_tests_properties(test_bluetoothagent PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
