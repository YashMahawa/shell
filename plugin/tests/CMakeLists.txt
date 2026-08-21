add_executable(test_voiceservice test_voiceservice.cpp)
target_link_libraries(test_voiceservice PRIVATE
    caelestia-services
    Qt::Core
    Qt::Gui
    Qt::Qml
    Qt::Test
    Qt::Network
    Qt::DBus
    PkgConfig::Pipewire
)
add_test(NAME test_voiceservice COMMAND test_voiceservice)
set_tests_properties(test_voiceservice PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
