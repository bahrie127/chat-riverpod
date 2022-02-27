// ignore_for_file: prefer_const_constructors

import 'package:chat/common_widgets/avatar.dart';
import 'package:chat/model/channel_model.dart';
import 'package:chat/model/message_model.dart';
import 'package:chat/model/user_model.dart';
import 'package:chat/service/firestore_database.dart';
import 'package:chat/view/chat/widgets/chat_bubble.dart';
import 'package:chat/view/chat/widgets/chat_footer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final messageStreamProvider =
    StreamProvider.autoDispose.family<List<Message>, String>((ref, channelId) {
  return FireStoreDatabase().messageStream(channelId);
});

class ChatPage extends StatefulWidget {
  const ChatPage({Key? key, this.channel, required this.oppositeUser}) : super(key: key);
  final Channel? channel;
  final UserModel oppositeUser;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  Channel? _channel;
  final _messageController = TextEditingController();
  final _currentUser = UserModel.fromFirebaseUser(FirebaseAuth.instance.currentUser!);

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 35,
        leading: CupertinoButton(
          child: const Icon(
            Icons.arrow_back_ios,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Avatar(photoURL: widget.oppositeUser.photoUrl),
            const SizedBox(width: 8),
            Text(widget.oppositeUser.displayName),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: Consumer(
                  builder: (context, ref, _) {
                    final _channelId = channelId(_currentUser.id, widget.oppositeUser.id);
                    final messages = ref.watch(messageStreamProvider(_channelId)).value;
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: ListView.separated(
                        physics: AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        reverse: true,
                        itemCount: messages?.length ?? 0,
                        itemBuilder: (context, index) {
                          if (messages?.isEmpty ?? true) {
                            return const SizedBox();
                          }
                          var direc = _currentUser.id == messages![index].senderId
                              ? Direction.right
                              : Direction.left;

                          BubbleType type = getType(messages, index);

                          return ChatBubble(
                            direction: direc,
                            message: messages[index].textMessage,
                            photoUrl: direc == Direction.left ? widget.oppositeUser.photoUrl : null,
                            type: type,
                          );
                        },
                        separatorBuilder: (context, index) {
                          return const SizedBox(height: 3);
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            ChatFooter(
              textController: _messageController,
              onSendMessage: onSendMessage,
            ),
          ],
        ),
      ),
    );
  }

  BubbleType getType(List<Message> messages, int index) {
    if (index == 0) {
      if (messages[index].senderId != messages[index + 1].senderId) {
        return BubbleType.alone;
      } else {
        return BubbleType.bottom;
      }
    } else if (index == messages.length - 1) {
      if (messages[index].senderId != messages[index - 1].senderId) {
        return BubbleType.alone;
      } else {
        return BubbleType.top;
      }
    } else {
      if (messages[index].senderId != messages[index - 1].senderId &&
          messages[index].senderId != messages[index + 1].senderId) {
        return BubbleType.alone;
      }
      if (messages[index].senderId == messages[index + 1].senderId &&
          messages[index].senderId == messages[index - 1].senderId) {
        return BubbleType.middle;
      }
      if (messages[index].senderId == messages[index + 1].senderId &&
          messages[index].senderId != messages[index - 1].senderId) {
        return BubbleType.bottom;
      }
      if (messages[index].senderId != messages[index + 1].senderId &&
          messages[index].senderId == messages[index - 1].senderId) {
        return BubbleType.top;
      }
    }
    return BubbleType.alone;
  }

  void onSendMessage() {
    if (_messageController.text.trim().isEmpty) {
      return;
    }
    // channel not created yet
    if (_channel == null) {
      _channel = Channel(
        id: channelId(_currentUser.id, widget.oppositeUser.id),
        memberIds: [_currentUser.id, widget.oppositeUser.id],
        members: [_currentUser, widget.oppositeUser],
        lastMessage: _messageController.text.trim(),
        sendBy: _currentUser.id,
        lastTime: Timestamp.now(),
        unRead: {
          _currentUser.id: false,
          widget.oppositeUser.id: true,
        },
      );

      FireStoreDatabase().updateChannel(_channel!.id, _channel!.toMap());
    }

    var docRef = FirebaseFirestore.instance.collection('messages').doc();
    var message = Message(
      id: docRef.id,
      textMessage: _messageController.text.trim(),
      senderId: _currentUser.id,
      sendAt: Timestamp.now(),
      channelId: _channel!.id,
    );
    FireStoreDatabase().addMessage(message);

    var channelUpdateData = {
      'lastMessage': message.textMessage,
      'sendBy': _currentUser.id,
      'lastTime': message.sendAt,
      'unRead': {
        _currentUser.id: false,
        widget.oppositeUser.id: true,
      },
    };
    FireStoreDatabase().updateChannel(_channel!.id, channelUpdateData);

    _messageController.clear();
  }
}
