import 'package:avataar_generator/generator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dash_chat/dash_chat.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

const Color primaryColor = Color.fromARGB(255, 245, 54, 88);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primaryColor: primaryColor,
        accentColor: primaryColor,
        primaryTextTheme: Theme.of(context)
            .textTheme
            .copyWith(headline6: TextStyle(color: Colors.white)),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'xpress'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const _pathCollection = 'messages';
  final GlobalKey<DashChatState> _chatViewKey = GlobalKey<DashChatState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: EdgeInsets.only(left: 16.0),
          child: Image.asset('assets/images/xpress_logo_white.png'),
        ),
        title: Text(widget.title),
      ),
      body: StreamBuilder(
        stream:
            FirebaseFirestore.instance.collection(_pathCollection).snapshots(),
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
            return Column(
              children: <Widget>[
                SvgPicture.string(
                  getSvg(Options()).replaceAll('path-', 'path'),
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
            );
          }
        },
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
}
