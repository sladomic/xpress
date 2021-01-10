import 'dart:async';
import 'dart:io';

import 'package:avataar_generator/enums.dart';
import 'package:firebase_ml_vision/firebase_ml_vision.dart' as ml;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:avataar_generator/generator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dash_chat/dash_chat.dart';
import 'package:flutter_svg/svg.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as im;
import 'package:path_provider/path_provider.dart';
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
  ml.FaceDetector _faceDetector;
  String _filePath;
  String _emotion = 'neutral';

  @override
  void initState() {
    super.initState();
    final List<CameraDescription> frontCameras = widget.cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.front)
        .toList();
    _faceDetector = ml.FirebaseVision.instance.faceDetector();
    if (frontCameras.length > 0) {
      _cameraController =
          CameraController(frontCameras.first, ResolutionPreset.medium);
      _cameraController.initialize().then(
        (_) async {
          if (!mounted) {
            return;
          }
          Tflite.loadModel(
                  model: "assets/models/emotion_classification_7.tflite",
                  labels: "assets/models/emotion_classification_labels.txt",
                  useGpuDelegate: false)
              .then((_) {
            _cameraController.addListener(() async {
              final file = File.fromUri(Uri.file(_filePath));
              if (file.existsSync()) {
                final faces = await detectFaces(file);
                if (faces.length > 0) {
                  await detectEmotion(file, faces.first.boundingBox);
                }
                await _takePictureDelayed();
              }
            });
            _takePictureDelayed();
          }); // TODO use GPU
        },
      );
    }
  }

  @override
  void dispose() async {
    _cameraController?.dispose();
    _faceDetector.close();
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

  Future<void> _takePictureDelayed() =>
      Future.delayed(Duration(milliseconds: 500), () async {
        String filePath = (await getTemporaryDirectory()).path +
            '/image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        setState(() {
          _filePath = filePath;
        });
        await _cameraController.takePicture(filePath);
      });

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

  Future<List<ml.Face>> detectFaces(File file) async {
    final visionImage = ml.FirebaseVisionImage.fromFile(file);
    return _faceDetector.processImage(visionImage);
  }

  Future<void> detectEmotion(File file, Rect face) async {
    final image = im.decodeJpg(file.readAsBytesSync());

    final cropped = im.copyCrop(
      image,
      face.left.toInt(),
      (face.bottom - face.height).toInt(),
      face.width.toInt(),
      face.height.toInt(),
    );
    final resized = im.copyResize(cropped, width: 48, height: 48);
    final grayscale = im.grayscale(resized);
    await file.writeAsBytes(im.encodeJpg(grayscale));

    final recognitions = await Tflite.runModelOnImage(
      path: _filePath,
      imageMean: 0,
      imageStd: 255,
    );

    if (recognitions.length > 0) {
      setState(() {
        _emotion = recognitions.first['label'];
      });
    }
  }
}
