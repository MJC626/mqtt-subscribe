# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

cmake_minimum_required(VERSION 3.16)
project(quicksubscription LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Charts Core Gui Mqtt Qml Quick)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(quicksubscription
    WIN32
    MACOSX_BUNDLE
    main.cpp
)

target_compile_definitions(quicksubscription PUBLIC
    QT_DEPRECATED_WARNINGS
)

target_link_libraries(quicksubscription PRIVATE
    Qt::Charts
    Qt::Core
    Qt::Gui
    Qt::Mqtt
    Qt::Qml
    Qt::Quick
)

qt_add_qml_module(quicksubscription
    URI subscription
    QML_FILES
        "Main.qml"
    SOURCES
        qmlmqttclient.cpp qmlmqttclient.h
        RESOURCES quicksubscription.qrc
)


if(WIN32)
    get_target_property(_qmake_executable Qt6::qmake IMPORTED_LOCATION)
    get_filename_component(_qt_bin_dir "${_qmake_executable}" DIRECTORY)
    find_program(WINDEPLOYQT_EXECUTABLE windeployqt HINTS "${_qt_bin_dir}")

    if(WINDEPLOYQT_EXECUTABLE)
      add_custom_command(TARGET quicksubscription POST_BUILD
          COMMAND "${WINDEPLOYQT_EXECUTABLE}"
                  --no-translations          # 不部署翻译文件
                  --no-system-d3d-compiler   # 不部署 D3D 编译器
                  --no-virtualkeyboard       # 不部署虚拟键盘
                  --no-opengl-sw             # 不部署软件 OpenGL
                  --no-svg                   # 如果不使用 SVG，可以移除
                  --compiler-runtime         # 只部署必要的编译器运行时
                  --qmldir "${CMAKE_CURRENT_SOURCE_DIR}"  # 指定 QML 目录以便只部署所需的 QML 模块
                  --release                  # 指定发布版本，减少调试信息
                  "$<TARGET_FILE:quicksubscription>"
          WORKING_DIRECTORY "$<TARGET_FILE_DIR:quicksubscription>"
          COMMENT "Deploying minimal Qt dependencies for quicksubscription..."
      )
    endif()
endif()
