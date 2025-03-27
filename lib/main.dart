import 'package:flutter/material.dart';
import 'package:chat_app/services/supabase_service.dart';
import 'package:chat_app/screens/login_screen.dart';
import 'package:chat_app/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  final supabaseService = SupabaseService();
  await supabaseService.initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final supabaseService = SupabaseService();
    final isLoggedIn = supabaseService.currentUser != null;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FlashChat',
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: isLoggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
