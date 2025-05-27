import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String? _overlayMessage;
  bool _isLoading = false;

  Future<void> _submitSupport() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      setState(() {
        _overlayMessage = 'Please fill in both Title and Content fields.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _overlayMessage = null; // Clear previous messages
    });

    try {
      final session = Supabase.instance.client.auth.currentSession;
      final email = session?.user.email ?? 'Unknown';
      final accessToken = session?.accessToken;

      if (accessToken == null) {
        setState(() {
          _overlayMessage = 'Authentication error. Please log in again.';
          _isLoading = false;
        });
        return;
      }

      // Call the edge function (replace with your deployed function URL)
      final url = Uri.parse('https://wufjuulwrcwxrpriytmg.supabase.co/functions/v1/report-support-issue');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'title': title,
          'content': content,
          'email': email,
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _overlayMessage = 'Your report has been submitted successfully. Our team will review your message.';
          _titleController.clear();
          _contentController.clear();
        });
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _overlayMessage = data['error'] ?? 'Failed to submit support request. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _overlayMessage = 'An error occurred: ${e.toString()}. Please check your connection and try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lilacPurple = colorScheme.primary;
    final darkText = colorScheme.onSurface;
    final lightGreyText = colorScheme.onSurface.withOpacity(0.6);
    final hintAndIconGrey = colorScheme.onSurface.withOpacity(0.5);
    final dividerAndBorderColor = colorScheme.onSurface.withOpacity(0.12);
    final cardBackground = colorScheme.surface;
    final scaffoldBackground = colorScheme.background;

    return Scaffold(
      backgroundColor: scaffoldBackground, // Theme-aware background
      // appBar: AppBar( // THIS LINE AND THE AppBar WIDGET HAVE BEEN REMOVED
      //   title: const Text('Support', style: TextStyle(color: darkText, fontWeight: FontWeight.bold)),
      //   backgroundColor: whiteColor,
      //   elevation: 0.5, // Subtle shadow for app bar
      //   iconTheme: const IconThemeData(color: darkText), // For back button or menu icon
      //   leading: IconButton( // Example leading icon (hamburger)
      //     icon: const Icon(Icons.menu),
      //     onPressed: () {
      //       // Handle menu action, e.g., Scaffold.of(context).openDrawer();
      //       // For now, just a placeholder action or remove if not needed
      //        ScaffoldMessenger.of(context).showSnackBar(
      //         const SnackBar(content: Text('Menu pressed')),
      //       );
      //     },
      //   ),
      // ),
      body: SafeArea( // Added SafeArea to ensure content is not obscured by system UI
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Card(
                    elevation: 4,
                    color: cardBackground,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.headset_mic_outlined, size: 56, color: lilacPurple),
                          const SizedBox(height: 16),
                          Text(
                            'Support & Feedback',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: lilacPurple,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Report a bug or suggest a feature. Our team will review your message.',
                            style: TextStyle(
                              fontSize: 15,
                              color: lightGreyText,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Divider(height: 1, color: dividerAndBorderColor, thickness: 1),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _titleController,
                            style: TextStyle(color: darkText),
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.title, color: hintAndIconGrey),
                              hintText: 'Title',
                              hintStyle: TextStyle(color: hintAndIconGrey),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: dividerAndBorderColor),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: lilacPurple, width: 2.0),
                              ),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _contentController,
                            style: TextStyle(color: darkText),
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.article_outlined, color: hintAndIconGrey),
                              hintText: 'Content',
                              hintStyle: TextStyle(color: hintAndIconGrey),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: dividerAndBorderColor),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: lilacPurple, width: 2.0),
                              ),
                            ),
                            maxLines: 4,
                            minLines: 2,
                            textInputAction: TextInputAction.done,
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _submitSupport,
                              icon: _isLoading
                                  ? Container(
                                      width: 20,
                                      height: 20,
                                      padding: const EdgeInsets.all(2.0),
                                      child: CircularProgressIndicator(
                                        color: darkText,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send, size: 20),
                              label: Text(_isLoading ? 'Submitting...' : 'Submit'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cardBackground,
                                foregroundColor: darkText,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30.0), // More rounded to match image
                                  side: BorderSide(color: dividerAndBorderColor, width: 1.5),
                                ),
                                elevation: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_overlayMessage != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Center(
                    child: Card(
                      color: cardBackground, // Changed from mutedPeach for better contrast with text
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                             Icon(
                              _overlayMessage!.toLowerCase().contains('success')
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                              color: _overlayMessage!.toLowerCase().contains('success')
                                ? Colors.green
                                : Colors.redAccent,
                              size: 40,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _overlayMessage!,
                              style: TextStyle(
                                color: darkText,
                                fontSize: 16,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _overlayMessage = null;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: lilacPurple,
                                foregroundColor: darkText, // Or whiteColor for better contrast on lilac
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                              ),
                              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}