qml_module(caelestia-images
    URI Caelestia.Images
    SOURCES
        cachingimageprovider.cpp
        imagecacher.cpp
        iutils.cpp
        wallpaperengine.cpp
        wallpaperengine.hpp
    LIBRARIES
        Qt::Gui
        Qt::Quick
        Qt::Concurrent
)
