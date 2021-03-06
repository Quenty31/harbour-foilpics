import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.foilpics 1.0

import "harbour"

Item {
    id: view

    property Page mainPage
    property var hints
    property var foilModel
    property bool isCurrentView
    readonly property bool ready: foilModel.foilState === FoilPicsModel.FoilPicsReady
    property alias remorseSelectionModel: listView.selectionModel
    property var selectionModel
    property bool dropSelectionModelsWhenDecryptionDone

    Component.onCompleted: {
        isCurrentView = parent.isCurrentItem
        listView.maximizeCacheBuffer()
    }

    onIsCurrentViewChanged: {
        if (!isCurrentView) {
            bulkActionRemorse.cancelNicely()
            dropSelectionModels()
        }
    }

    EncryptedList {
        id: listView

        clip: true
        anchors.fill: parent
        foilModel: view.foilModel
        model: foilModel.groupModel
        busy: foilModel.busy || progressTimer.running
        //: Encrypted grid title
        //% "Encrypted"
        title: qsTrId("foilpics-encrypted_grid-title")

        PullDownMenu {
            visible: view.ready
            MenuItem {
                id: generateKeyMenuItem
                //: Pulley menu item
                //% "Generate a new key"
                text: qsTrId("foilpics-pulley_menu-generate_key")
                visible: !foilModel.count
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("GenerateKeyPage.qml"), {
                        foilModel: foilModel
                    })
                }
            }
            MenuItem {
                //: Pulley menu item
                //% "Change password"
                text: qsTrId("foilpics-pulley_menu-change_password")
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("ChangePasswordPage.qml"), {
                        mainPage: view.mainPage,
                        foilModel: foilModel
                    })
                }
            }
            MenuItem {
                id: selectPhotosMenuItem
                //: Pulley menu item
                //% "Select photos"
                text: qsTrId("foilpics-pulley_menu-select_photos")
                visible: foilModel.count > 0
                onClicked: selectPictures()
            }
        }

        ViewPlaceholder {
            text: hints.letsEncryptSomething < MaximumHintCount ?
                //: Placeholder text with a hint
                //% "Why not to encrypt something?"
                qsTrId("foilpics-encrypted_grid-placeholder-no_pictures_hint") :
                //: Placeholder text
                //% "You don't have any encrypted pictures"
                qsTrId("foilpics-encrypted_grid-placeholder-no_pictures")
            enabled: !view.busy && foilModel && foilModel.count === 0
        }
    }

    Connections {
        target: foilModel
        onBusyChanged: {
            if (foilModel.busy) {
                // Look busy for at least a second
                progressTimer.start()
            } else if (dropSelectionModelsWhenDecryptionDone) {
                dropSelectionModelsWhenDecryptionDone = false
                dropSelectionModels()
            }
        }
        onDecryptionStarted: leftSwipeToDecryptedHintLoader.armed = true
    }

    // The parent loader is supposed to have isCurrentItem property
    Connections {
        target: parent
        onIsCurrentItemChanged: isCurrentView = target.isCurrentItem
    }

    Timer {
        id: progressTimer

        interval: 1000
        running: true
    }

    // Selection model is fairly expensive, we create and maintain it
    // only in selection mode
    Component {
        id: selectionModelComponent

        FoilPicsSelection {
            model: foilModel
            role: "imageId"
            duplicatesAllowed: false
        }
    }

    RemorsePopup {
        id: bulkActionRemorse

        function cancelNicely() {
            // To avoid flickering, do it only when really necessary
            if (visible) cancel()
        }
        onCanceled: dropSelectionModels()
    }

    function dropSelectionModels() {
        if (remorseSelectionModel) {
            remorseSelectionModel.destroy()
            remorseSelectionModel = null
        }
        if (selectionModel) {
            selectionModel.destroy()
            selectionModel = null
        }
    }

    function bulkAction(text, list, callback) {
        listView.jumpToIndex(list[0])
        remorseSelectionModel = selectionModelComponent.createObject(page)
        remorseSelectionModel.makeBusy(list)
        pageStack.pop()
        bulkActionRemorse.execute(text, callback)
    }

    function selectPictures() {
        dropSelectionModels()
        bulkActionRemorse.cancelNicely()
        selectionModel = selectionModelComponent.createObject(page)
        var selectionPage = pageStack.push(Qt.resolvedUrl("EncryptedSelectionPage.qml"), {
            allowedOrientations: page.allowedOrientations,
            selectionModel: view.selectionModel,
            foilModel: view.foilModel
        })
        selectionPage.deletePictures.connect(function(list) {
            //: Generic remorse popup text
            //% "Deleting %0 selected pictures"
            bulkAction(qsTrId("foilpics-remorse-deleting_selected", list.length).arg(list.length), list, function() {
                foilModel.removeFiles(list)
                dropSelectionModels()
            })
        })
        selectionPage.groupPictures.connect(function(list) {
            var groups = foilModel.groupModel
            var groupPage = pageStack.push(Qt.resolvedUrl("EditGroupPage.qml"), {
                groupModel: groups
            })
            groupPage.groupSelected.connect(function(index) {
                foilModel.setGroupIdForRows(list, groups.groupId(index))
                dropSelectionModels()
                pageStack.pop(mainPage)
            })
        })
        selectionPage.decryptPictures.connect(function(list) {
            //: Remorse popup text
            //% "Decrypting %0 selected pictures"
            bulkAction(qsTrId("foilpics-encrypted_pics_view-remorse-decrypting_selected", list.length).arg(list.length), list, function() {
                console.log(list)
                foilModel.decryptFiles(list)
                if (foilModel.busy) {
                    dropSelectionModelsWhenDecryptionDone = true
                } else {
                    // Well, this shouldn't happen but just in case...
                    dropSelectionModels()
                }
            })
        })
    }

    Connections {
        target: mainPage
        onStatusChanged: maybeDropSelectionModel()
    }

    Connections {
        target: pageStack
        onCurrentPageChanged: maybeDropSelectionModel()
    }

    function maybeDropSelectionModel() {
        if (selectionModel && mainPage.status === PageStatus.Active && pageStack.currentPage === mainPage) {
            console.log("dropping selection model")
            selectionModel.destroy()
            selectionModel = null
        }
    }

    Loader {
        id: leftSwipeToDecryptedHintLoader

        anchors.fill: parent
        active: opacity > 0
        opacity: ((hints.leftSwipeToDecrypted < MaximumHintCount && armed) | running) ? 1 : 0
        property bool armed
        property bool running
        sourceComponent: Component {
            HarbourHorizontalSwipeHint {
                //: Left swipe hint text
                //% "Decrypted pictures are moved back to the gallery"
                text: qsTrId("foilpics-hint-swipe_left_to_decrypted")
                hintEnabled: leftSwipeToDecryptedHintLoader.armed && !hintDelayTimer.running
                onHintShown: {
                    hints.leftSwipeToDecrypted++
                    leftSwipeToDecryptedHintLoader.armed = false
                }
                onHintRunningChanged: leftSwipeToDecryptedHintLoader.running = hintRunning
                Timer {
                    id: hintDelayTimer
                    interval: 1000
                    running: true
                }
            }
        }
        Behavior on opacity { FadeAnimation {} }
    }
}
