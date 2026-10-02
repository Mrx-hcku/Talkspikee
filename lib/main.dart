import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const TalkSpikeApp());
}

class TalkSpikeApp extends StatelessWidget {
  const TalkSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TalkSpike',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D16),
        primaryColor: const Color(0xFF22C55E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22C55E),
          secondary: Color(0xFFF43F5E),
          surface: Color(0xFF111827),
        ),
      ),
      home: const AuthCheckScreen(),
    );
  }
}

class AuthCheckScreen extends StatelessWidget {
  const AuthCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Color(0xFF22C55E))),
          );
        }
        if (snapshot.hasData) {
          return const MainScreenContainer();
        }
        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  String _getRandomAvatar(String uid) {
    return 'https://i.pravatar.cc/150?u=$uid';
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;

      if (googleAuth != null && googleAuth.accessToken != null && googleAuth.idToken != null) {
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        UserCredential userCreds = await FirebaseAuth.instance.signInWithCredential(credential);
        
        String? fcmToken = await FirebaseMessaging.instance.getToken();
        if (userCreds.user != null) {
          await FirebaseFirestore.instance.collection('users').doc(userCreds.user!.uid).set({
            'uid': userCreds.user!.uid,
            'name': userCreds.user!.displayName ?? 'User',
            'email': userCreds.user!.email ?? '',
            'photoUrl': userCreds.user!.photoURL ?? _getRandomAvatar(userCreds.user!.uid),
            'fcmToken': fcmToken ?? '',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login Failed: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.bolt, size: 50, color: Color(0xFF22C55E)),
              ),
              const SizedBox(height: 16),
              const Text(
                'TalkSpike',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'A text-first community discussion platform',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              _isLoading
                  ? const CircularProgressIndicator(color: Color(0xFF22C55E))
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 30),
                      label: const Text(
                        'Continue with Google',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScreenContainer extends StatefulWidget {
  const MainScreenContainer({super.key});

  @override
  State<MainScreenContainer> createState() => _MainScreenContainerState();
}

class _MainScreenContainerState extends State<MainScreenContainer> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const ExploreScreen(),
    const NotificationsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF090D16),
          border: Border(top: BorderSide(color: Color(0xFF1F2937), width: 1)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home, 0),
            _buildNavItem(Icons.tag, 1),
            GestureDetector(
              onTap: () {
                setState(() => _currentIndex = 0);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.black, size: 24),
              ),
            ),
            _buildNavItem(Icons.notifications_outlined, 2),
            _buildNavItem(Icons.person_outline, 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index) {
    final bool isSelected = _currentIndex == index;
    return IconButton(
      icon: Icon(
        icon,
        color: isSelected ? const Color(0xFF22C55E) : Colors.grey,
        size: 26,
      ),
      onPressed: () => setState(() => _currentIndex = index),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _postController = TextEditingController();
  String _selectedTag = '#tech';
  String _feedFilter = 'All';

  String _getRandomAvatar(String uid) {
    return 'https://i.pravatar.cc/150?u=$uid';
  }

  void _publishPost() async {
    if (_postController.text.trim().isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('posts').add({
        'authorId': user.uid,
        'author': user.displayName ?? 'Anonymous User',
        'handle': '@${user.email?.split('@')[0] ?? 'user'}',
        'authorPic': user.photoURL ?? _getRandomAvatar(user.uid),
        'content': '${_postController.text.trim()} $_selectedTag',
        'tag': _selectedTag,
        'likes': 0,
        'likedBy': [],
        'timestamp': FieldValue.serverTimestamp(),
      });
      _postController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thought published successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _toggleLike(String docId, String postOwnerId, List<dynamic> likedBy) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef = FirebaseFirestore.instance.collection('posts').doc(docId);
    List<String> updatedLikedBy = List<String>.from(likedBy);

    if (updatedLikedBy.contains(user.uid)) {
      updatedLikedBy.remove(user.uid);
      await docRef.update({
        'likes': FieldValue.increment(-1),
        'likedBy': updatedLikedBy,
      });
    } else {
      updatedLikedBy.add(user.uid);
      await docRef.update({
        'likes': FieldValue.increment(1),
        'likedBy': updatedLikedBy,
      });

      if (user.uid != postOwnerId) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'receiverId': postOwnerId,
          'senderName': user.displayName ?? 'Someone',
          'title': 'New Like',
          'body': '${user.displayName ?? 'Someone'} liked your discussion.',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF22C55E), size: 20),
            ),
            const SizedBox(width: 8),
            const Text(
              'TalkSpike',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF090D16),
        actions: [
          IconButton(
            icon: const Icon(Icons.dark_mode_outlined, color: Colors.grey),
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: CircleAvatar(
              radius: 16,
              backgroundImage: currentUser?.photoURL != null
                  ? NetworkImage(currentUser!.photoURL!)
                  : NetworkImage(_getRandomAvatar(currentUser?.uid ?? 'default')),
              backgroundColor: const Color(0xFF22C55E),
            ),
          ),
        ],
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Home Feed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                Row(
                  children: ['All', 'Following', '#Tech'].map((filter) {
                    final bool isActive = _feedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: GestureDetector(
                        onTap: () => setState(() => _feedFilter = filter),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive ? const Color(0xFF22C55E) : const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            filter,
                            style: TextStyle(
                              color: isActive ? Colors.black : Colors.grey.shade400,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1F2937)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _postController,
                  maxLines: 3,
                  maxLength: 280,
                  decoration: const InputDecoration(
                    hintText: "What's sparking your mind today? Share thoughts, debate ideas, ask questions...",
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                    border: InputBorder.none,
                    counterStyle: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: ['#tech', '#AI', '#debate'].map((tag) {
                        final bool isSelected = _selectedTag == tag;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedTag = tag),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF22C55E).withOpacity(0.2) : const Color(0xFF1F2937),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isSelected ? const Color(0xFF22C55E) : Colors.transparent),
                              ),
                              child: Text(tag, style: TextStyle(color: isSelected ? const Color(0xFF22C55E) : Colors.grey, fontSize: 12)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: _publishPost,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Publish Thought', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                )
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1F2937)),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('posts').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No discussions yet. Be the first to spark one!', style: TextStyle(color: Colors.grey)));
                }

                final docs = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final List<dynamic> likedBy = data['likedBy'] ?? [];
                    final bool isLiked = currentUser != null && likedBy.contains(currentUser.uid);
                    final String postOwnerId = data['authorId'] ?? '';
                    final String authorPic = data['authorPic'] ?? _getRandomAvatar(postOwnerId);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFF1F2937), width: 1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundImage: NetworkImage(authorPic),
                                backgroundColor: const Color(0xFF22C55E),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(data['author'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text(data['handle'] ?? '@user', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                                ],
                              ),
                              const Spacer(),
                              Text('Just now', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                              const SizedBox(width: 6),
                              const Icon(Icons.more_horiz, color: Colors.grey, size: 18),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(data['content'] ?? '', style: const TextStyle(fontSize: 14, height: 1.4)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildActionRow(Icons.chat_bubble_outline, '0'),
                              _buildActionRow(Icons.repeat, '0'),
                              InkWell(
                                onTap: () => _toggleLike(doc.id, postOwnerId, likedBy),
                                child: Row(
                                  children: [
                                    Icon(
                                      isLiked ? Icons.favorite : Icons.favorite_border,
                                      size: 18,
                                      color: isLiked ? Colors.redAccent : Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text('${data['likes'] ?? 0}', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.share_outlined, size: 18, color: Colors.grey),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(IconData icon, String count) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 4),
        Text(count, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
      ],
    );
  }
}

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF22C55E), size: 20),
            ),
            const SizedBox(width: 8),
            const Text('TalkSpike', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20)),
          ],
        ),
        backgroundColor: const Color(0xFF090D16),
        actions: [
          const Icon(Icons.dark_mode_outlined, color: Colors.grey),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: CircleAvatar(
              radius: 16,
              backgroundImage: currentUser?.photoURL != null ? NetworkImage(currentUser!.photoURL!) : null,
              backgroundColor: const Color(0xFF22C55E),
              child: currentUser?.photoURL == null ? const Icon(Icons.person, size: 18, color: Colors.black) : null,
            ),
          ),
        ],
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Explore Trends', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search topics, tags, or thinkers...',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFF111827),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Trending Right Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          _buildTrendCard('Technology', '#tech', '14.2K discussions'),
          _buildTrendCard('Artificial Intelligence', '#AI', '38.9K discussions'),
          _buildTrendCard('Mind & Society', '#philosophy', '9.4K discussions'),
        ],
      ),
    );
  }

  Widget _buildTrendCard(String category, String tag, String count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              const SizedBox(height: 4),
              Text(tag, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(count, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ],
          ),
          const Icon(Icons.trending_up, color: Color(0xFF22C55E), size: 24),
        ],
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF22C55E), size: 20),
            ),
            const SizedBox(width: 8),
            const Text('TalkSpike', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20)),
          ],
        ),
        backgroundColor: const Color(0xFF090D16),
        actions: [
          const Icon(Icons.dark_mode_outlined, color: Colors.grey),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: CircleAvatar(
              radius: 16,
              backgroundImage: currentUser?.photoURL != null ? NetworkImage(currentUser!.photoURL!) : null,
              backgroundColor: const Color(0xFF22C55E),
              child: currentUser?.photoURL == null ? const Icon(Icons.person, size: 18, color: Colors.black) : null,
            ),
          ),
        ],
        elevation: 0,
      ),
      body: currentUser == null
          ? const Center(child: Text('Please login to see notifications'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('receiverId', isEqualTo: currentUser.uid)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No notifications yet', style: TextStyle(color: Colors.grey)));
                }

                final docs = snapshot.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF22C55E).withOpacity(0.2),
                            child: const Icon(Icons.notifications, color: Color(0xFF22C55E), size: 16),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['title'] ?? 'Notification', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text(data['body'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {}),
        title: Text(currentUser?.displayName ?? 'Profile', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF090D16),
        actions: [
          const Icon(Icons.dark_mode_outlined, color: Colors.grey),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: CircleAvatar(
              radius: 16,
              backgroundImage: currentUser?.photoURL != null ? NetworkImage(currentUser!.photoURL!) : null,
              backgroundColor: const Color(0xFF22C55E),
              child: currentUser?.photoURL == null ? const Icon(Icons.person, size: 18, color: Colors.black) : null,
            ),
          ),
        ],
        elevation: 0,
      ),
      body: ListView(
        children: [
          Container(
            height: 120,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green, Colors.indigo, Colors.purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  offset: const Offset(0, -35),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Color(0xFF090D16), shape: BoxShape.circle),
                        child: CircleAvatar(
                          radius: 38,
                          backgroundImage: currentUser?.photoURL != null ? NetworkImage(currentUser!.photoURL!) : null,
                          backgroundColor: const Color(0xFF22C55E),
                          child: currentUser?.photoURL == null ? const Icon(Icons.person, size: 45, color: Colors.black) : null,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade600),
                        ),
                        child: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(currentUser?.displayName ?? 'Anonymous User', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(currentUser?.email ?? '@user', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                      const SizedBox(height: 12),
                      const Text(
                        'Software architect and open web advocate exploring decentralized discussions and clean code philosophy.',
                        style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text('Joined March 2023', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                          const SizedBox(width: 20),
                          const Text('384', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                          const SizedBox(width: 4),
                          Text('Following', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                          const SizedBox(width: 16),
                          const Text('1420', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                          const SizedBox(width: 4),
                          Text('Followers', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1F2937), height: 1),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              TabItem(title: 'Discussions', isActive: true),
              TabItem(title: 'Replies', isActive: false),
              TabItem(title: 'Likes', isActive: false),
            ],
          ),
          const Divider(color: Color(0xFF1F2937), height: 1),
        ],
      ),
    );
  }
}

class TabItem extends StatelessWidget {
  final String title;
  final bool isActive;
  const TabItem({super.key, required this.title, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Text(
        title,
        style: TextStyle(
          color: isActive ? const Color(0xFF22C55E) : Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
