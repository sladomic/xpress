import 'dart:async';

import 'package:avataar_generator/enums.dart';
import 'package:flutter/material.dart';
import 'package:avataar_generator/generator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dash_chat/dash_chat.dart';
import 'package:flutter_svg/svg.dart';
import 'package:camera/camera.dart';
import 'package:tflite/tflite.dart';

const Color primaryColor = Color.fromARGB(255, 245, 54, 88);

final Map<String, String> emotionMap = {
  'anger': getSvg(
      Options(eyes: Eyes.squint, eyebrow: Eyebrow.angry, mouth: Mouth.serious)),
  'disgust': getSvg(
      Options(eyes: Eyes.dizzy, eyebrow: Eyebrow.upDown, mouth: Mouth.vomit)),
  'fear': getSvg(Options(
      eyes: Eyes.squint,
      eyebrow: Eyebrow.sadConcerned,
      mouth: Mouth.concerned)),
  'happy': getSvg(Options(
      eyes: Eyes.happy, eyebrow: Eyebrow.raisedExcited, mouth: Mouth.smile)),
  'sad': getSvg(
      Options(eyes: Eyes.cry, eyebrow: Eyebrow.sadConcerned, mouth: Mouth.sad)),
  'surprise': getSvg(Options(
      eyes: Eyes.surprised,
      eyebrow: Eyebrow.raisedExcited,
      mouth: Mouth.disbelief)),
  'neutral': getSvg(
      Options(eyes: Eyes.none, eyebrow: Eyebrow.none, mouth: Mouth.none)),
};

class App extends StatefulWidget {
  final List<CameraDescription> cameras;

  App({@required this.cameras});

  @override
  State<StatefulWidget> createState() => AppState();
}

class AppState extends State<App> {
  final String _pathCollection = 'messages';
  final GlobalKey<DashChatState> _chatViewKey = GlobalKey<DashChatState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  CameraController _cameraController;
  Timer _timer;
  String _emotion = 'neutral';
  int _timestamp = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    final List<CameraDescription> frontCameras = widget.cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.front)
        .toList();
    if (frontCameras.length > 0) {
      _cameraController =
          CameraController(frontCameras.first, ResolutionPreset.medium);
      _cameraController.initialize().then((_) {
        if (!mounted) {
          return;
        }
        Tflite.loadModel(
                model: "assets/models/emotion_classification_7.tflite",
                labels: "assets/models/emotion_classification_labels.txt",
                useGpuDelegate: false)
            .then((_) => _cameraController.startImageStream((image) {
                  if (DateTime.now()
                          .difference(
                              DateTime.fromMillisecondsSinceEpoch(_timestamp))
                          .inSeconds >
                      1) {
                    _timestamp = DateTime.now().millisecondsSinceEpoch;
                    recognizeImageBinary(image);
                  }
                })); // TODO use GPU
      });
    }
  }

  @override
  void dispose() async {
    _cameraController?.dispose();
    _timer.cancel();
    await Tflite.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xpress',
      theme: ThemeData(
        primaryColor: primaryColor,
        accentColor: primaryColor,
        primaryTextTheme: Theme.of(context)
            .textTheme
            .copyWith(headline6: TextStyle(color: Colors.white)),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          leading: Padding(
            padding: EdgeInsets.only(left: 16.0),
            child: Image.asset('assets/images/logos/xpress_logo_white.png'),
          ),
          title: Text('xpress'),
        ),
        body: StreamBuilder(
          stream: FirebaseFirestore.instance
              .collection(_pathCollection)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return Center(
                child: Text(snapshot.error.toString()),
              );
            else if (!snapshot.hasData) {
              return Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).primaryColor,
                  ),
                ),
              );
            } else {
              List<DocumentSnapshot> items = snapshot.data.documents;
              var messages =
                  items.map((i) => ChatMessage.fromJson(i.data())).toList();
              return Stack(
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      SvgPicture.string(
                        emotionMap[_emotion].replaceAll('path-', 'path'),
                        height: MediaQuery.of(context).size.height / 4,
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: DashChat(
                            key: _chatViewKey,
                            user: ChatUser(),
                            onSend: onSend,
                            messages: messages,
                          ),
                        ),
                      )
                    ],
                  )
                ],
              );
            }
          },
        ),
      ),
    );
  }

  void onSend(ChatMessage message) {
    var documentReference = FirebaseFirestore.instance
        .collection(_pathCollection)
        .doc(DateTime.now().millisecondsSinceEpoch.toString());

    FirebaseFirestore.instance.runTransaction((transaction) async {
      transaction.set(
        documentReference,
        message.toJson(),
      );
    });
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    _scaffoldKey.currentState.showSnackBar(SnackBar(content: Text(message)));
  }

  Future recognizeImageBinary(CameraImage cameraImage) async {
    int startTime = new DateTime.now().millisecondsSinceEpoch;
    var recognitions = await Tflite.runModelOnFrame(
      bytesList:
          cameraImage.planes.map((plane) => plane.bytes).toList(), // required
      imageHeight: cameraImage.height,
      imageWidth: cameraImage.width,
      imageMean: 0,
      imageStd: 255,
      numResults: 1,
      threshold: 0.3,
      rotation: _cameraController.description.sensorOrientation,
    );
    if (recognitions.length > 0)
      setState(() {
        _emotion = recognitions.first['label'];
      });
    int endTime = new DateTime.now().millisecondsSinceEpoch;
    print("Inference took ${endTime - startTime}ms");
  }
}
