import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:convert';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  late IO.Socket socket;
  String? currentUserId;

  factory SocketService() {
    return _instance;
  }

  SocketService._internal();

  void initialize(String userId) {
    currentUserId = userId;
    
    // Connect to your Socket.io server
    // Note: You'll need to set up a Node.js server with Socket.io
    socket = IO.io('https://your-socket-server.com', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'query': {'userId': userId}
    });

    socket.connect();
    
    socket.onConnect((_) {
      print('Socket connected');
    });
    
    socket.onDisconnect((_) {
      print('Socket disconnected');
    });
    
    socket.onError((error) {
      print('Socket error: $error');
    });
  }

  void sendMessage(String receiverId, Map<String, dynamic> message) {
    socket.emit('send_message', {
      'senderId': currentUserId,
      'receiverId': receiverId,
      'message': message,
    });
  }

  void listenForMessages(Function(Map<String, dynamic>) onMessageReceived) {
    socket.on('receive_message', (data) {
      final messageData = data is String ? json.decode(data) : data;
      onMessageReceived(messageData);
    });
  }

  void disconnect() {
    socket.disconnect();
  }
}