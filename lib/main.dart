import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

const Color kBg = Color(0xFF090D16);
const Color kGreen = Color(0xFF22C55E);
const Color kCard = Color(0xFF111827);
const Color kBorder = Color(0xFF1F2937);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Koi bhi build error aaye to blank/grey screen ki jagah message dikhega.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: kBg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Something went wrong:\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  };

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
        scaffoldBackgroundColor: kBg,
        primaryColor: kGreen,
        colorScheme: const ColorScheme.dark(
          primary: kGreen,
          secondary: Color(0xFFF43F5E),
          surface: kCard,
        ),
      ),
      home: const AppGate(),
    );
  }
}

/// Firebase initialise hone tak splash dikhata hai.
/// Init fail ho to error + Retry dikhata hai (blank screen nahi).
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initFirebase();
  }

  Future<void> _initFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp().timeout(const Duration(seconds: 20));
    }
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('FCM background handler error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        if (snapshot.hasError) {
          return _InitErrorScreen(
            error: snapshot.error.toString(),
            onRetry: () => setState(() => _initFuture = _initFirebase()),
          );
        }
        return const AuthCheckScreen();
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBg,
      body: Center(child: CircularProgressIndicator(color: kGreen)),
    );
  }
}

class _InitErrorScreen extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _InitErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
                'App start nahi ho paayi',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.black,
                ),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
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
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: kBg,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Something went wrong: ${snapshot.error}',
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const MainScreenContainer();
        }
        return const LoginScreen();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> signOutUser() async {
  try {
    await GoogleSignIn().signOut();
  } catch (_) {}
  await FirebaseAuth.instance.signOut();
}

String timeAgo(dynamic ts) {
  if (ts is! Timestamp) return 'Just now';
  final date = ts.toDate();
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${date.day}/${date.month}/${date.year}';
}

class UserAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  const UserAvatar({super.key, required this.url, required this.radius});

  @override
  Widget build(BuildContext context) {
    final bool hasUrl = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: kGreen,
      backgroundImage: hasUrl ? NetworkImage(url!) : null,
      onBackgroundImageError: hasUrl ? (_, __) {} : null,
      child: hasUrl ? null : Icon(Icons.person, size: radius, color: Colors.black),
    );
  }
}

AppBar buildTalkSpikeAppBar(User? user) {
  return AppBar(
    backgroundColor: kBg,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    title: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: kGreen.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.bolt, color: kGreen, size: 20),
        ),
        const SizedBox(width: 8),
        const Text(
          'TalkSpike',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
        ),
      ],
    ),
    actions: [
      const Icon(Icons.dark_mode_outlined, color: Colors.grey),
      const SizedBox(width: 16),
      Padding(
        padding: const EdgeInsets.only(right: 12.0),
        child: UserAvatar(url: user?.photoURL, radius: 16),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

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
      if (googleUser == null) return; // user ne cancel kiya

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final UserCredential userCreds =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final User? user = userCreds.user;

      if (user != null) {
        // Login ho chuka hai; profile save fail ho to bhi login fail nahi dikhana.
        unawaited(_saveUserProfile(user));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login Failed: $e'),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveUserProfile(User user) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      await userRef.set({
        'uid': user.uid,
        'name': user.displayName ?? 'User',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? _getRandomAvatar(user.uid),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('User profile save error: $e');
    }

    try {
      await FirebaseMessaging.instance
          .requestPermission()
          .timeout(const Duration(seconds: 10));
      final String? token =
          await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 10));
      if (token != null) {
        await userRef.set({'fcmToken': token}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.bolt, size: 50, color: kGreen),
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
                  ? const CircularProgressIndicator(color: kGreen)
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

// ---------------------------------------------------------------------------
// Main container (bottom nav)
// ---------------------------------------------------------------------------

class MainScreenContainer extends StatefulWidget {
  const MainScreenContainer({super.key});

  @override
  State<MainScreenContainer> createState() => _MainScreenContainerState();
}

class _MainScreenContainerState extends State<MainScreenContainer> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    ExploreScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: kBg,
            border: Border(top: BorderSide(color: kBorder, width: 1)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, 0),
              _buildNavItem(Icons.tag, 1),
              GestureDetector(
                onTap: () => setState(() => _currentIndex = 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: kGreen.withOpacity(0.4),
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
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index) {
    final bool isSelected = _currentIndex == index;
    return IconButton(
      icon: Icon(icon, color: isSelected ? kGreen : Colors.grey, size: 26),
      onPressed: () => setState(() => _currentIndex = index),
    );
  }
}

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _postController = TextEditingController();
  String _selectedTag = '#tech';
  String _feedFilter = 'All';
  bool _isPosting = false;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _postsStream;

  @override
  void initState() {
    super.initState();
    _postsStream = FirebaseFirestore.instance
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  String _getRandomAvatar(String uid) {
    return 'https://i.pravatar.cc/150?u=$uid';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _publishPost() async {
    final String text = _postController.text.trim();
    if (text.isEmpty || _isPosting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isPosting = true);
    try {
      await FirebaseFirestore.instance.collection('posts').add({
        'authorId': user.uid,
        'author': user.displayName ?? 'Anonymous User',
        'handle': '@${user.email?.split('@')[0] ?? 'user'}',
        'authorPic': user.photoURL ?? _getRandomAvatar(user.uid),
        'content': '$text $_selectedTag',
        'tag': _selectedTag,
        'likes': 0,
        'likedBy': [],
        'timestamp': FieldValue.serverTimestamp(),
      });
      _postController.clear();
      if (mounted) FocusScope.of(context).unfocus();
      _showMessage('Thought published successfully!');
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _toggleLike(String docId, String postOwnerId, bool isLiked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef = FirebaseFirestore.instance.collection('posts').doc(docId);
    try {
      if (isLiked) {
        await docRef.update({
          'likes': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove([user.uid]),
        });
      } else {
        await docRef.update({
          'likes': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([user.uid]),
        });

        if (user.uid != postOwnerId && postOwnerId.isNotEmpty) {
          try {
            await FirebaseFirestore.instance.collection('notifications').add({
              'receiverId': postOwnerId,
              'senderName': user.displayName ?? 'Someone',
              'title': 'New Like',
              'body': '${user.displayName ?? 'Someone'} liked your discussion.',
              'timestamp': FieldValue.serverTimestamp(),
            });
          } catch (e) {
            debugPrint('Notification error: $e');
          }
        }
      }
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: kBg,
      appBar: buildTalkSpikeAppBar(currentUser),
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(child: _buildHeaderAndComposer()),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _postsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Posts load nahi ho paaye: ${snapshot.error}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator(color: kGreen)),
                  ),
                );
              }

              List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                  snapshot.data?.docs ?? [];
              if (_feedFilter == '#Tech') {
                docs = docs.where((d) => d.data()['tag'] == '#tech').toList();
              } else if (_feedFilter == 'Following') {
                docs = [];
              }

              if (docs.isEmpty) {
                final String msg = _feedFilter == 'Following'
                    ? 'Following feed jaldi aa raha hai.'
                    : 'No discussions yet. Be the first to spark one!';
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(msg, style: const TextStyle(color: Colors.grey)),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildPost(docs[index], currentUser),
                  childCount: docs.length,
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildHeaderAndComposer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Home Feed',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
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
                          color: isActive ? kGreen : kCard,
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
            color: kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _postController,
                maxLines: 3,
                maxLength: 280,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText:
                      "What's sparking your mind today? Share thoughts, debate ideas, ask questions...",
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                  border: InputBorder.none,
                  counterStyle: TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                spacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: ['#tech', '#AI', '#debate'].map((tag) {
                      final bool isSelected = _selectedTag == tag;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTag = tag),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? kGreen.withOpacity(0.2) : kBorder,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected ? kGreen : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                color: isSelected ? kGreen : Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    onPressed: _isPosting ? null : _publishPost,
                    icon: _isPosting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.edit, size: 16),
                    label: const Text(
                      'Publish Thought',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: kBorder),
      ],
    );
  }

  Widget _buildPost(QueryDocumentSnapshot<Map<String, dynamic>> doc, User? currentUser) {
    final data = doc.data();
    final List<dynamic> likedBy = (data['likedBy'] as List<dynamic>?) ?? [];
    final bool isLiked = currentUser != null && likedBy.contains(currentUser.uid);
    final String postOwnerId = (data['authorId'] ?? '').toString();
    final String authorPic = (data['authorPic'] ?? _getRandomAvatar(postOwnerId)).toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(url: authorPic, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (data['author'] ?? 'Anonymous').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                    Text(
                      (data['handle'] ?? '@user').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                timeAgo(data['timestamp']),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.more_horiz, color: Colors.grey, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            (data['content'] ?? '').toString(),
            style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildActionRow(Icons.chat_bubble_outline, '0'),
              _buildActionRow(Icons.repeat, '0'),
              InkWell(
                onTap: () => _toggleLike(doc.id, postOwnerId, isLiked),
                child: Row(
                  children: [
                    Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: isLiked ? Colors.redAccent : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${data['likes'] ?? 0}',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.share_outlined, size: 18, color: Colors.grey),
            ],
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

// ---------------------------------------------------------------------------
// Explore
// ---------------------------------------------------------------------------

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: kBg,
      appBar: buildTalkSpikeAppBar(currentUser),
      body: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Text(
            'Explore Trends',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search topics, tags, or thinkers...',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: kCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Trending Right Now',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
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
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                tag,
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(count, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ],
          ),
          const Icon(Icons.trending_up, color: kGreen, size: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // orderBy hata diya: where + orderBy ke liye Firestore composite index
      // chahiye hota hai (bina index ke list khali dikhti thi). Sort neeche local hota hai.
      _stream = FirebaseFirestore.instance
          .collection('notifications')
          .where('receiverId', isEqualTo: user.uid)
          .snapshots();
    }
  }

  int _millis(dynamic ts) {
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    return DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: kBg,
      appBar: buildTalkSpikeAppBar(currentUser),
      body: _stream == null
          ? const Center(
              child: Text('Please login to see notifications',
                  style: TextStyle(color: Colors.grey)),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Notifications load nahi ho paaye: ${snapshot.error}',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: kGreen));
                }
                final docs = (snapshot.data?.docs ?? []).toList()
                  ..sort((a, b) =>
                      _millis(b.data()['timestamp']).compareTo(_millis(a.data()['timestamp'])));

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No notifications yet', style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kBorder),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: kGreen.withOpacity(0.2),
                            child: const Icon(Icons.notifications, color: kGreen, size: 16),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (data['title'] ?? 'Notification').toString(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (data['body'] ?? '').toString(),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13, height: 1.3),
                                ),
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

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _joinedText(User? user) {
    final DateTime? d = user?.metadata.creationTime;
    if (d == null) return 'Joined recently';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return 'Joined ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(
          currentUser?.displayName ?? 'Profile',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: Colors.grey),
            onPressed: signOutUser,
          ),
          const SizedBox(width: 4),
        ],
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
                        decoration: const BoxDecoration(color: kBg, shape: BoxShape.circle),
                        child: UserAvatar(url: currentUser?.photoURL, radius: 38),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade600),
                        ),
                        child: const Text(
                          'Edit Profile',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUser?.displayName ?? 'Anonymous User',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentUser?.email ?? '@user',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Welcome to TalkSpike - share thoughts, debate ideas and discover discussions.',
                        style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                _joinedText(currentUser),
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('0',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 13)),
                              const SizedBox(width: 4),
                              Text('Following',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('0',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 13)),
                              const SizedBox(width: 4),
                              Text('Followers',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: kBorder, height: 1),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              TabItem(title: 'Discussions', isActive: true),
              TabItem(title: 'Replies', isActive: false),
              TabItem(title: 'Likes', isActive: false),
            ],
          ),
          const Divider(color: kBorder, height: 1),
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
          color: isActive ? kGreen : Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
