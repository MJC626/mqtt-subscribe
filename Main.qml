import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtCharts

Window {
    visible: true
    width: 800
    height: 600
    title: qsTr("MQTT订阅")
    id: root

    // 核心属性
    property var tempSubscription: 0
    property var parsedData: ({})
    property int currentGroup: 0
    property var availableGroups: []
    property bool initialLoad: true
    property int maxMessages: 100
    property int autoCleanInterval: 1 // 默认1分钟（用户看到的单位）
    property int internalCleanupInterval: autoCleanInterval * 60000 // 内部使用的毫秒数
    property var customLabels: ({})      // 存储自定义标签
    property var customUnits: ({})       // 存储自定义单位
    property var customFormulas: ({})    // 存储自定义公式
    property var dataHistory: ({})       // 存储数据历史记录
    property var recordIntervals: ({})   // 存储数据记录间隔

    // MQTT客户端
    MqttClient {
        id: client
        hostname: hostnameField.text
        port: portField.text
    }

    // 消息列表模型
    ListModel {
        id: messageModel
    }

    // 可视化数据模型
    ListModel {
        id: visualizationModel
    }

    // 自动清理定时器
    Timer {
        id: cleanupTimer
        interval: root.internalCleanupInterval
        running: true // 始终运行，通过条件控制是否执行清理
        repeat: true
        onTriggered: {
            if (messageModel.count > 0) {
                console.log("Auto cleanup triggered at", new Date().toLocaleTimeString())
                messageModel.clear()
            }
        }
    }

    // 解析并计算数学表达式
    function evaluateFormula(formula, value) {
        try {
            // 替换"值"为实际的value
            let expression = formula.replace(/值/g, value.toString());

            // 安全检查，确保只包含合法的数学表达式
            if (!/^[0-9\s\+\-\*\/\(\)\.\,]*$/.test(expression)) {
                console.error("Invalid expression: " + expression);
                return value; // 如果表达式不合法，返回原值
            }

            // 使用Function构造器计算表达式
            let result = new Function('return ' + expression)();
            return parseFloat(result);
        } catch (e) {
            console.error("Expression evaluation error:", e);
            return value; // 如果计算出错，返回原值
        }
    }

    // 核心函数：解析数据
    function parseData(payload) {
        try {
            const data = JSON.parse(payload);
            parsedData = data;

            if (initialLoad) {
                availableGroups = Object.keys(data);
                initialLoad = false;
            } else {
                const newGroups = Object.keys(data);
                for (let i = 0; i < newGroups.length; i++) {
                    if (!availableGroups.includes(newGroups[i])) {
                        availableGroups.push(newGroups[i]);
                    }
                }
            }

            updateVisualization();
            return true;
        } catch (e) {
            console.error("Failed to parse data:", e);
            return false;
        }
    }

    // 更新可视化数据
    function updateVisualization() {
        if (availableGroups.length === 0) return;

        const groupKey = availableGroups[currentGroup];
        const groupData = parsedData[groupKey];

        visualizationModel.clear();

        if (Array.isArray(groupData)) {
            for (let i = 0; i < groupData.length; i++) {
                const itemId = groupKey + "_" + i;
                let label = "Value " + (i + 1);
                let unit = "";
                let rawValue = groupData[i];
                let displayValue = rawValue;

                if (root.customLabels[itemId]) {
                    label = root.customLabels[itemId];
                }

                if (root.customUnits[itemId]) {
                    unit = root.customUnits[itemId];
                }

                // 应用自定义公式
                if (root.customFormulas[itemId]) {
                    displayValue = evaluateFormula(root.customFormulas[itemId], rawValue);
                }

                visualizationModel.append({
                    id: i,
                    itemId: itemId,
                    rawValue: rawValue,
                    displayValue: displayValue,
                    label: label,
                    unit: unit,
                    formula: root.customFormulas[itemId] || ""
                });
            }
        }
    }

    // 添加消息
    function addMessage(payload) {
        messageModel.insert(0, {"payload": payload})

        if (messageModel.count >= maxMessages) {
            messageModel.remove(maxMessages - 1)
        }

        parseData(payload)
    }
    // 曲线图窗口组件
    Component {
        id: chartWindowComponent
        Window {
            id: chartWindow
            width: 800
            height: 600
            title: ""

            property string currentItemId: ""
            property bool isRecording: false
            property int recordInterval: 1000
            property bool useKalmanFilter: false  // 卡尔曼滤波开关
            property real kalmanQ: 1.0         // 过程噪声协方差
            property real kalmanR: 1.0          // 测量噪声协方差
            property real kalmanP: 1.0           // 估计误差协方差
            property real kalmanX: 0.0           // 状态估计值
            property int maxDataPoints: 100      // X轴最大显示点数

            // 卡尔曼滤波函数
            function kalmanFilter(measurement) {
                // 预测步骤
                kalmanP = kalmanP + kalmanQ;
                
                // 更新步骤
                const kalmanK = kalmanP / (kalmanP + kalmanR);  // 卡尔曼增益
                kalmanX = kalmanX + kalmanK * (measurement - kalmanX);
                kalmanP = (1 - kalmanK) * kalmanP;
                
                return kalmanX;
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                // 控制面板
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Label { text: "记录间隔(ms):" }

                    SpinBox {
                        id: intervalSpinBox
                        from: 100
                        to: 10000
                        stepSize: 100
                        value: chartWindow.recordInterval
                        onValueChanged: {
                            if (chartWindow.currentItemId) {
                                recordIntervals[chartWindow.currentItemId] = value;
                                recordTimer.interval = value;
                            }
                        }
                    }

                    Button {
                        text: chartWindow.isRecording ? "停止记录" : "开始记录"
                        onClicked: {
                            chartWindow.isRecording = !chartWindow.isRecording;
                            if (chartWindow.isRecording) {
                                if (!dataHistory[chartWindow.currentItemId]) {
                                    dataHistory[chartWindow.currentItemId] = {
                                        data: [],
                                        isRecording: true
                                    };
                                } else {
                                    dataHistory[chartWindow.currentItemId].isRecording = true;
                                }
                                recordTimer.start();
                            } else {
                                if (dataHistory[chartWindow.currentItemId]) {
                                    dataHistory[chartWindow.currentItemId].isRecording = false;
                                }
                                recordTimer.stop();
                            }
                        }
                    }

                    Button {
                        text: "清除数据"
                        onClicked: {
                            if (dataHistory[chartWindow.currentItemId]) {
                                dataHistory[chartWindow.currentItemId].data = [];
                                lineSeries.clear();
                            }
                        }
                    }

                    CheckBox {
                        text: "卡尔曼滤波"
                        checked: chartWindow.useKalmanFilter
                        onCheckedChanged: {
                            chartWindow.useKalmanFilter = checked;
                            // 重置卡尔曼滤波器状态
                            kalmanP = 1.0;
                            kalmanX = 0.0;
                        }
                    }
                }

                // X轴数据点控制面板
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Label { text: "X轴最大点数:" }
                    SpinBox {
                        id: maxPointsSpinBox
                        from: 10
                        to: 1000
                        stepSize: 10
                        value: chartWindow.maxDataPoints
                        onValueChanged: {
                            chartWindow.maxDataPoints = value;
                        }
                    }
                }

                // 卡尔曼滤波参数控制面板
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: chartWindow.useKalmanFilter

                    Label { text: "Q值(过程噪声):" }
                    SpinBox {
                        id: spinBoxQ
                        from: 1  // 对应 0.01
                        to: 10000  // 对应 100
                        stepSize: 1  // 对应 0.01
                        value: Math.round(chartWindow.kalmanQ * 100)
                        editable: true

                        property int decimals: 2
                        onValueModified: {
                            chartWindow.kalmanQ = value / 100;
                            // 重置滤波器状态
                            kalmanP = 1.0;
                            kalmanX = 0.0;
                        }

                        textFromValue: function(value, locale) {
                            return Number(value / 100).toLocaleString(locale, 'f', decimals)
                        }

                        valueFromText: function(text, locale) {
                            return Math.round(Number.fromLocaleString(locale, text) * 100)
                        }
                    }

                    Label { text: "R值(测量噪声):" }
                    SpinBox {
                        id: spinBoxR
                        from: 1  // 对应 0.01
                        to: 10000  // 对应 100
                        stepSize: 1  // 对应 0.01
                        value: Math.round(chartWindow.kalmanR * 100)
                        editable: true

                        property int decimals: 2
                        onValueModified: {
                            chartWindow.kalmanR = value / 100;
                            // 重置滤波器状态
                            kalmanP = 1.0;
                            kalmanX = 0.0;
                        }

                        textFromValue: function(value, locale) {
                            return Number(value / 100).toLocaleString(locale, 'f', decimals)
                        }

                        valueFromText: function(text, locale) {
                            return Math.round(Number.fromLocaleString(locale, text) * 100)
                        }
                    }
                }


                // 图表视图
                ChartView {
                    id: chartView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    antialiasing: true

                    DateTimeAxis {
                        id: axisX
                        format: "mm:ss"
                        titleText: "时间"
                    }

                    ValueAxis {
                        id: axisY
                        titleText: "值"
                    }

                    LineSeries {
                        id: lineSeries
                        axisX: axisX
                        axisY: axisY
                        name: chartWindow.title
                    }
                }
            }

            // 图表更新定时器
            Timer {
                id: updateTimer
                interval: 300
                running: chartWindow.visible && chartWindow.isRecording
                repeat: true
                onTriggered: {
                    if (chartWindow.currentItemId && dataHistory[chartWindow.currentItemId] && dataHistory[chartWindow.currentItemId].isRecording) {
                        const data = dataHistory[chartWindow.currentItemId].data;
                        lineSeries.clear();
                        if (data.length > 0) {
                            // 限制数据点数量
                            let displayData = data;
                            if (data.length > chartWindow.maxDataPoints) {
                                displayData = data.slice(data.length - chartWindow.maxDataPoints);
                            }
                            
                            // 更新X轴范围
                            const firstTime = displayData[0].timestamp;
                            const lastTime = displayData[displayData.length - 1].timestamp;
                            axisX.min = new Date(firstTime);
                            axisX.max = new Date(lastTime);

                            // 更新Y轴范围
                            let minY = displayData[0].value;
                            let maxY = displayData[0].value;

                            // 绘制数据点
                            displayData.forEach(point => {
                                let value = point.value;
                                if (chartWindow.useKalmanFilter) {
                                    value = chartWindow.kalmanFilter(value);
                                }
                                lineSeries.append(point.timestamp, value);
                                minY = Math.min(minY, value);
                                maxY = Math.max(maxY, value);
                            });

                            // 设置Y轴范围
                            if (minY === maxY) {
                                axisY.min = minY - 1;
                                axisY.max = maxY + 1;
                            } else {
                                const padding = (maxY - minY) * 0.1;
                                axisY.min = minY - padding;
                                axisY.max = maxY + padding;
                            }
                        }
                    }
                }
            }

            // 数据记录定时器
            Timer {
                id: recordTimer
                interval: chartWindow.recordInterval
                running: false
                repeat: true
                onTriggered: {
                    if (chartWindow.currentItemId && dataHistory[chartWindow.currentItemId] && dataHistory[chartWindow.currentItemId].isRecording) {
                        const groupKey = availableGroups[currentGroup];
                        const groupData = parsedData[groupKey];
                        if (Array.isArray(groupData)) {
                            const parts = chartWindow.currentItemId.split("_");
                            const index = parseInt(parts[parts.length-1]);
                            const now = Date.now();

                            let valueToRecord = groupData[index];

                            // 应用公式（如果有）
                            if (root.customFormulas[chartWindow.currentItemId]) {
                                valueToRecord = evaluateFormula(root.customFormulas[chartWindow.currentItemId], valueToRecord);
                            }

                            dataHistory[chartWindow.currentItemId].data.push({
                                timestamp: now,
                                value: valueToRecord
                            });
                        }
                    }
                }
            }
        }
    }

    // 编辑对话框
    Dialog {
        id: editDialog
        title: "编辑数据"
        modal: true
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.8, 400)
        standardButtons: Dialog.Save | Dialog.Cancel

        property int currentIndex: -1
        property string currentItemId: ""
        property real currentRawValue: 0
        property string currentLabel: ""
        property string currentUnit: ""
        property string currentFormula: ""

        onAccepted: {
            if (currentIndex >= 0 && currentIndex < visualizationModel.count) {
                // 保存标签和单位
                root.customLabels[currentItemId] = labelEditField.text;
                root.customUnits[currentItemId] = unitEditField.text;

                // 保存公式
                let formula = formulaEditField.text.trim();
                if (formula.length > 0) {
                    root.customFormulas[currentItemId] = formula;
                } else {
                    delete root.customFormulas[currentItemId];
                }

                // 计算新的显示值
                let displayValue = currentRawValue;
                if (formula.length > 0) {
                    displayValue = evaluateFormula(formula, currentRawValue);
                }

                // 更新模型
                visualizationModel.setProperty(currentIndex, "label", labelEditField.text);
                visualizationModel.setProperty(currentIndex, "unit", unitEditField.text);
                visualizationModel.setProperty(currentIndex, "formula", formula);
                visualizationModel.setProperty(currentIndex, "displayValue", displayValue);
            }
        }

        ColumnLayout {
            width: parent.width
            spacing: 15

            RowLayout {
                Layout.fillWidth: true
                Label { text: "原始值:"; Layout.preferredWidth: 80; font.pixelSize: 14 }
                Label { id: rawValueDisplay; text: ""; font.pixelSize: 16; font.bold: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "计算值:"; Layout.preferredWidth: 80; font.pixelSize: 14 }
                Label { id: calculatedValueDisplay; text: ""; font.pixelSize: 16; font.bold: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "组 ID:"; Layout.preferredWidth: 80; font.pixelSize: 14 }
                Label { id: itemIdDisplay; text: ""; font.pixelSize: 14; elide: Text.ElideRight }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "标签:"; Layout.preferredWidth: 80; font.pixelSize: 14 }
                TextField { id: labelEditField; Layout.fillWidth: true; placeholderText: "输入标签" }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "单位:"; Layout.preferredWidth: 80; font.pixelSize: 14 }
                TextField { id: unitEditField; Layout.fillWidth: true; placeholderText: "输入单位" }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5

                Label { text: "数学运算:"; font.pixelSize: 14 }
                TextField {
                    id: formulaEditField;
                    Layout.fillWidth: true;
                    placeholderText: "例如：(值+10)/7, 值*10, 值-5..."
                    onTextChanged: {
                        // 即时计算并显示结果
                        if (text.trim().length > 0) {
                            try {
                                let result = evaluateFormula(text, editDialog.currentRawValue);
                                calculatedValueDisplay.text = result.toFixed(2);
                            } catch (e) {
                                calculatedValueDisplay.text = "(公式错误)";
                            }
                        } else {
                            calculatedValueDisplay.text = editDialog.currentRawValue.toFixed(2);
                        }
                    }
                }

                Label {
                    text: "提示: 使用\"值\"作为原始数据的占位符。支持+, -, *, /, 和括号。"
                    font.pixelSize: 12
                    color: "#666666"
                }
            }
        }

        function openForEdit(index, itemId, rawValue, displayValue, label, unit, formula) {
            currentIndex = index
            currentItemId = itemId
            currentRawValue = rawValue
            currentLabel = label
            currentUnit = unit
            currentFormula = formula || ""

            rawValueDisplay.text = rawValue.toFixed(2)
            calculatedValueDisplay.text = displayValue.toFixed(2)
            itemIdDisplay.text = itemId
            labelEditField.text = label
            unitEditField.text = unit
            formulaEditField.text = currentFormula

            open()
            labelEditField.forceActiveFocus()
        }
    }

    // 主布局
    StackLayout {
        id: mainLayout
        anchors.fill: parent
        currentIndex: 0

        // 第一页 - MQTT连接
        Item {
            GridLayout {
                anchors.fill: parent
                anchors.margins: 10
                columns: 2

                Label {
                    text: "主机名:"
                    enabled: client.state === MqttClient.Disconnected
                }

                TextField {
                    id: hostnameField
                    Layout.fillWidth: true
                    text: "626.mjc626.cloudns.org"
                    placeholderText: "<mqtt服务器>"
                    enabled: client.state === MqttClient.Disconnected
                }

                Label {
                    text: "端口:"
                    enabled: client.state === MqttClient.Disconnected
                }

                TextField {
                    id: portField
                    Layout.fillWidth: true
                    text: "1883"
                    placeholderText: "<端口号>"
                    inputMethodHints: Qt.ImhDigitsOnly
                    enabled: client.state === MqttClient.Disconnected
                }

                Label {
                    text: "自动清理（分钟）:"
                    enabled: client.state === MqttClient.Disconnected
                }

                TextField {
                    id: cleanupField
                    Layout.fillWidth: true
                    text: root.autoCleanInterval.toString()
                    placeholderText: "<分钟>"
                    inputMethodHints: Qt.ImhDigitsOnly
                    enabled: client.state === MqttClient.Disconnected
                    onTextChanged: {
                        if (text.length > 0 && parseInt(text) > 0) {
                            root.autoCleanInterval = parseInt(text)
                            root.internalCleanupInterval = root.autoCleanInterval * 60000
                            cleanupTimer.interval = root.internalCleanupInterval
                            console.log("Cleanup interval set to", root.autoCleanInterval, "minutes")
                        }
                    }
                }

                Button {
                    id: connectButton
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    text: client.state === MqttClient.Connected ? "断开连接" : "连接"
                    onClicked: {
                        if (client.state === MqttClient.Connected) {
                            client.disconnectFromHost()
                            messageModel.clear()
                            visualizationModel.clear()
                            root.parsedData = {}
                            root.availableGroups = []
                            root.initialLoad = true
                            cleanupTimer.stop()
                            if (root.tempSubscription) {
                                root.tempSubscription.destroy()
                                root.tempSubscription = 0
                            }
                        } else {
                            client.connectToHost()
                        }
                    }
                }

                RowLayout {
                    enabled: client.state === MqttClient.Connected
                    Layout.columnSpan: 2
                    Layout.fillWidth: true

                    Label { text: "主题:" }

                    TextField {
                        id: subField
                        placeholderText: "<订阅主题>"
                        Layout.fillWidth: true
                        enabled: root.tempSubscription === 0
                    }

                    Button {
                        id: subButton
                        text: "订阅"
                        visible: root.tempSubscription === 0
                        onClicked: {
                            if (subField.text.length === 0) {
                                console.log("No topic specified to subscribe to.")
                                return
                            }
                            tempSubscription = client.subscribe(subField.text)
                            tempSubscription.messageReceived.connect(addMessage)
                            cleanupTimer.start()
                        }
                    }
                }

                ListView {
                    id: messageView
                    model: messageModel
                    implicitHeight: 200
                    implicitWidth: 200
                    Layout.columnSpan: 2
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    clip: true
                    delegate: Rectangle {
                        id: delegatedRectangle
                        required property int index
                        required property string payload
                        width: ListView.view.width
                        height: 30
                        color: index % 2 ? "#DDDDDD" : "#888888"
                        radius: 5

                        Text {
                            text: delegatedRectangle.payload
                            anchors.centerIn: parent
                            elide: Text.ElideRight
                            width: parent.width - 20
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                Button {
                    id: clearButton
                    text: "清理"
                    Layout.fillWidth: true
                    enabled: messageModel.count > 0
                    onClicked: {
                        messageModel.clear()
                    }
                }

                Label {
                    function stateToString(value) {
                        if (value === 0) return "未连接"
                        else if (value === 1) return "连接中"
                        else if (value === 2) return "已连接"
                        else return "未知"
                    }

                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    color: "#333333"
                    text: "状态: " + stateToString(client.state)
                }

                Button {
                    text: "可视化页面"
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    enabled: availableGroups.length > 0
                    onClicked: {
                        mainLayout.currentIndex = 1
                    }
                }
            }
        }

        // 第二页 - 数据可视化
        Item {
            GridLayout {
                anchors.fill: parent
                anchors.margins: 10
                columns: 1
                rowSpacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: availableGroups.length > 0 ? "组: " + availableGroups[currentGroup] : "无数据"
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "上一组"
                        enabled: currentGroup > 0
                        onClicked: {
                            currentGroup--
                            updateVisualization()
                        }
                    }

                    Button {
                        text: "下一组"
                        enabled: currentGroup < availableGroups.length - 1
                        onClicked: {
                            currentGroup++
                            updateVisualization()
                        }
                    }

                    Button {
                        text: "返回"
                        onClicked: {
                            mainLayout.currentIndex = 0
                        }
                    }
                }

                ScrollView {
                    id: visualizationScrollView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    GridLayout {
                        width: visualizationScrollView.width
                        columns: 2
                        columnSpacing: 20
                        rowSpacing: 20
                        property bool hasOddItems: visualizationModel.count % 2 === 1

                        Repeater {
                            model: visualizationModel
                            delegate: Rectangle {
                                required property int index
                                required property var model

                                Layout.fillWidth: true
                                Layout.preferredHeight: 100
                                Layout.columnSpan: parent.hasOddItems && index === visualizationModel.count - 1 ? 2 : 1

                                color: "#f0f0f0"
                                border.color: "#cccccc"
                                border.width: 1
                                radius: 5

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        Text {
                                            text: model.label
                                            font.pixelSize: 14
                                            color: "#666666"
                                        }

                                        Text {
                                            text: model.displayValue.toFixed(2)
                                            font.pixelSize: 16
                                            font.bold: true
                                            Layout.alignment: Qt.AlignLeft
                                        }

                                        Text {
                                            text: model.unit
                                            font.pixelSize: 14
                                            color: "#666666"
                                            visible: model.unit !== ""
                                        }

                                        Item { Layout.fillWidth: true }

                                        Button {
                                            id: chartButton
                                            text: "曲线图"
                                            onClicked: {
                                                var window = chartWindowComponent.createObject(root);
                                                window.currentItemId = model.itemId;
                                                window.title = model.label + " - 数据曲线";
                                                window.recordInterval = recordIntervals[model.itemId] || 1000;
                                                window.isRecording = false;
                                                window.show();
                                            }
                                        }
                                    }

                                    // 如果有公式，显示公式和原始值
                                    Row {
                                        visible: model.formula && model.formula.length > 0
                                        spacing: 5

                                        Text {
                                            text: "公式: " + model.formula + " (原始值: " + model.rawValue.toFixed(2) + ")"
                                            font.pixelSize: 12
                                            color: "#666666"
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.rightMargin: chartButton.width + 10
                                    onDoubleClicked: {
                                        editDialog.openForEdit(index, model.itemId, model.rawValue, model.displayValue, model.label, model.unit, model.formula)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
