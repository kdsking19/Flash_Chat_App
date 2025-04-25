import 'package:flutter/material.dart';
import 'package:chat_app/services/supabase_service.dart';
import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/screens/chat_screen.dart';
import 'package:chat_app/screens/login_screen.dart';
import 'package:chat_app/screens/ai_chat_screen.dart';
import 'package:chat_app/screens/user_chat_list_screen.dart';
import 'package:provider/provider.dart';
import 'package:chat_app/providers/theme_provider.dart';

// Wrapper class to hold UserModel and recent chat preview
class UserWithRecentChat {
  final UserModel user;
  String recentChatPreview;

  UserWithRecentChat({required this.user, required this.recentChatPreview});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabaseService = SupabaseService();
  List<UserModel> _users = [];
  List<UserWithRecentChat> _usersWithRecentChats = [];
  List<UserWithRecentChat> _filteredUsersWithRecentChats = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _setupMessageListener();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setupMessageListener() {
    _supabaseService.listenForMessages((message) {
      _loadRecentChats(); // Instead of _loadUsers();
    });
  }


  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final usersData = await _supabaseService.getUsers();
      setState(() {
        _users = usersData
            .map((userData) => UserModel.fromJson(userData))
            .toList();
      });
      _loadRecentChats();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadRecentChats() async {
    try {
      // Fetch last messages for all users (placeholder implementation)
      final userIds = _users.map((user) => user.id).where((id) => id != null).toList();
      final lastMessages = await _getLastMessagesForUsers(userIds.cast<String>());

      // Transform users into UserWithRecentChat objects with last message, filtering out those without messages
      final userChats = _users
          .where((user) => user.id != null && lastMessages[user.id!] != null)
          .map((user) {
        final lastMessage = lastMessages[user.id!]!;
        final preview = lastMessage.length > 20
            ? '${lastMessage.substring(0, 20)}...'
            : lastMessage;
        return UserWithRecentChat(user: user, recentChatPreview: preview);
      }).toList();

      setState(() {
        _usersWithRecentChats = userChats;
        _filteredUsersWithRecentChats = userChats;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading recent chats: ${e.toString()}')),
        );
      }
    }
  }

  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsersWithRecentChats = _usersWithRecentChats;
      } else {
        _filteredUsersWithRecentChats = _usersWithRecentChats
            .where((userChat) {
              final user = userChat.user;
              final username = user.username?.toLowerCase() ?? '';
              final email = user.email?.toLowerCase() ?? '';
              final messagePreview = userChat.recentChatPreview.toLowerCase();
              final searchLower = query.toLowerCase();
              
              return username.contains(searchLower) || 
                     email.contains(searchLower) || 
                     messagePreview.contains(searchLower);
            })
            .toList();
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _filteredUsersWithRecentChats = _usersWithRecentChats;
      }
    });
  }

  Future<Map<String, String>> _getLastMessagesForUsers(List<String> userIds) async {
  final currentUserId = _supabaseService.currentUser?.id;
  if (currentUserId == null) return {};

  final response = await _supabaseService.client
      .from('messages')
      .select('sender_id, receiver_id, content, created_at')
      .or('sender_id.in.(${userIds.join(",")}),receiver_id.in.(${userIds.join(",")})')
      .or('receiver_id.eq.$currentUserId,sender_id.in.(${userIds.join(",")})')
      .order('created_at', ascending: false);

  // Map to hold the latest message per user
  final Map<String, String> lastMessages = {};

  for (var message in response) {
    final senderId = message['sender_id'];
    final receiverId = message['receiver_id'];
    final content = message['content'];

    // Determine who is the "other" user in this chat
    final otherUserId = senderId == currentUserId ? receiverId : senderId;

    // If this user doesn't already have a stored message, use this one (first one is the latest because of sort)
    if (!lastMessages.containsKey(otherUserId)) {
      lastMessages[otherUserId] = content;
    }
  }

  return lastMessages;
}

  Future<void> _logout() async {
    try {
      await _supabaseService.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: ${e.toString()}')),
        );
      }
    }
  }

  Future<Map<String, String>> _fetchLastMessagesForUsers(List<String> userIds) async {
  final currentUserId = _supabaseService.currentUser?.id;
  final Map<String, String> latestMessages = {};

  for (final userId in userIds) {
    final response = await _supabaseService.client
        .from('messages')
        .select('content, created_at')
        .or('sender_id.eq.$currentUserId,receiver_id.eq.$userId')
        .or('sender_id.eq.$userId,receiver_id.eq.$currentUserId')
        .order('created_at', ascending: false)
        .limit(1)
        .single();

    if (response != null && response['content'] != null) {
      latestMessages[userId] = response['content'] as String;
    }
  }

  return latestMessages;
}


  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return Scaffold(
      backgroundColor: isDarkMode ? Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDarkMode ? Color(0xFF1E1E1E) : Colors.white,
        title: _isSearching 
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search contacts...',
                  hintStyle: TextStyle(
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                ),
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
                onChanged: _filterUsers,
              )
            : Text(
                'Flash Chat',
                style: TextStyle(
                  color: Color(0xFF00B0FF),
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: Color(0xFF00B0FF),
            ),
            onPressed: _toggleSearch,
          ),
          if (!_isSearching) ...[
            IconButton(
              icon: Icon(
                isDarkMode ? Icons.light_mode : Icons.dark_mode,
                color: Color(0xFF00B0FF),
              ),
              onPressed: () {
                themeProvider.toggleTheme();
              },
            ),
            IconButton(
              icon: Icon(Icons.smart_toy, color: Color(0xFF00B0FF)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AIChatScreen()),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.logout, color: Color(0xFF00B0FF)),
              onPressed: _logout,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Color(0xFF00B0FF)))
          : _filteredUsersWithRecentChats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isSearching ? Icons.search_off : Icons.chat_bubble_outline,
                        size: 70,
                        color: isDarkMode ? Colors.grey[700] : Colors.grey[400],
                      ),
                      SizedBox(height: 16),
                      Text(
                        _isSearching ? 'No matching contacts found' : 'No recent chats available',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_isSearching) ...[
                        SizedBox(height: 8),
                        Text(
                          'Try a different search term',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _filteredUsersWithRecentChats.length,
                  itemBuilder: (context, index) {
                    final userChat = _filteredUsersWithRecentChats[index];
                    final user = userChat.user;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 0.5,
                      color: isDarkMode ? Color(0xFF2C2C2C) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF00B0FF), Color(0xFF0091EA)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Center(
                            child: Text(
                              user.email != null && user.email!.isNotEmpty
                                  ? user.email![0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          user.username ?? user.email ?? 'Unknown User',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          userChat.recentChatPreview,
                          style: TextStyle(
                            color: isDarkMode ? Colors.grey[400] : Colors.grey,
                          ),
                        ),
                        trailing: user.unreadCount > 0
                            ? Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Color(0xFF00B0FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  user.unreadCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isDarkMode ? Color(0xFF3C3C3C) : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  Icons.arrow_forward_ios,
                                  color: isDarkMode ? Colors.grey[400] : Colors.grey.shade600,
                                  size: 16,
                                ),
                              ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(user: user),
                            ),
                          ).then((_) => _loadUsers()); // Refresh on return
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFF00B0FF),
        elevation: 4,
        child: const Icon(Icons.message, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UserChatListScreen(users: _users)),
          );
        },
      ),
      drawer: Drawer(
        child: Container(
          color: isDarkMode ? Color(0xFF121212) : Colors.white,
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                decoration: BoxDecoration(color: Color(0xFF00B0FF)),
                accountName: Text(
                  _supabaseService.currentUser?.email?.split('@')[0] ?? 'User',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
                accountEmail: Text(
                  _supabaseService.currentUser?.email ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    _supabaseService.currentUser?.email != null &&
                            _supabaseService.currentUser!.email!.isNotEmpty
                        ? _supabaseService.currentUser!.email![0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00B0FF),
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color: Color(0xFF00B0FF)
                ),
                title: Text(
                  isDarkMode ? 'Light Mode' : 'Dark Mode',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                onTap: () {
                  themeProvider.toggleTheme();
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.smart_toy, color: Color(0xFF00B0FF)),
                title: Text(
                  'Chat with Llama AI',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AIChatScreen()),
                  );
                },
              ),
              Divider(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[300],
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: Text(
                  'Logout',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _logout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}