import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AICopilotFAB extends StatefulWidget {
  final Widget child;
  final String currentScreenName;
  final Map<String, dynamic>? activeContextData;

  const AICopilotFAB({
    super.key,
    required this.child,
    required this.currentScreenName,
    this.activeContextData,
  });

  @override
  State<AICopilotFAB> createState() => _AICopilotFABState();
}

class _AICopilotFABState extends State<AICopilotFAB> {
  void _openCopilotBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CopilotSheet(
        screenName: widget.currentScreenName,
        contextData: widget.activeContextData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          bottom: 20,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'ai_copilot_fab_${widget.currentScreenName}',
            onPressed: () => _openCopilotBottomSheet(context),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 6,
            icon: const Icon(Icons.smart_toy_rounded, color: Colors.white),
            label: const Text(
              'AI Copilot',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _CopilotSheet extends StatefulWidget {
  final String screenName;
  final Map<String, dynamic>? contextData;

  const _CopilotSheet({
    required this.screenName,
    this.contextData,
  });

  @override
  State<_CopilotSheet> createState() => _CopilotSheetState();
}

class _CopilotSheetState extends State<_CopilotSheet> {
  final TextEditingController _inputController = TextEditingController();
  final List<Map<String, String>> _chatHistory = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Add context greeting message
    _chatHistory.add({
      'role': 'assistant',
      'content': _getInitialGreeting(widget.screenName, widget.contextData),
    });
  }

  String _getInitialGreeting(String screen, Map<String, dynamic>? data) {
    switch (screen) {
      case 'Gap Analysis':
        return '👋 I am your GAHAR AI Copilot for **Gap Analysis**. Ask me how to close any compliance gap or suggest a corrective action plan!';
      case 'Requirements':
        return '👋 I am your GAHAR AI Copilot. Ask me to explain any GAHAR requirement (e.g. GSR, PCC, SAS, IPC) or evaluate applicability for your facility.';
      case 'Action Plans':
        return '👋 I am your GAHAR Copilot for **Action Plans**. Ask me to draft steps, assign responsibility, or estimate completion timelines.';
      case 'Documents':
        return '👋 I am your GAHAR Copilot for **Document Management**. Ask me to generate a policy draft (v1.0), SOP, or audit an existing document.';
      case 'Survey Readiness':
        return '👋 I am your GAHAR Copilot for **Survey Preparation**. Ask me "What are we missing for the accreditation audit?"';
      default:
        return '👋 Hello! I am your **GAHAR AI Copilot**. I understand your current context (**${widget.screenName}**). How can I assist your quality team today?';
    }
  }

  List<String> _getQuickPrompts(String screen) {
    switch (screen) {
      case 'Gap Analysis':
        return [
          'How to close critical gaps?',
          'Generate action plan for IPC gap',
          'What evidence is required?'
        ];
      case 'Requirements':
        return [
          'Explain PCC.06 requirement',
          'Is SAS.03 applicable for daycare?',
          'Show mandatory policies'
        ];
      case 'Documents':
        return [
          'Generate IPC Policy v1.0',
          'Draft Surgical Checklist SOP',
          'Review current policy compliance'
        ];
      case 'Survey Readiness':
        return [
          'Show critical missing items',
          'What are high risk areas?',
          'Generate Mock Survey checklist'
        ];
      default:
        return [
          'Summarize compliance status',
          'What is our target date readiness?',
          'Help with GAHAR standards'
        ];
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userQuery = text.trim();
    _inputController.clear();

    setState(() {
      _chatHistory.add({'role': 'user', 'content': userQuery});
      _loading = true;
    });

    final reply = await ApiService.getCopilotResponse(
      prompt: userQuery,
      screenContext: widget.screenName,
      entityData: widget.contextData,
    );

    if (mounted) {
      setState(() {
        _chatHistory.add({'role': 'assistant', 'content': reply});
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final quickPrompts = _getQuickPrompts(widget.screenName);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.smart_toy_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'GAHAR AI Copilot',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Context: ${widget.screenName}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Quick Prompts Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: quickPrompts.map((prompt) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    label: Text(
                      prompt,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () => _sendMessage(prompt),
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1),

          // Chat Messages View
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _chatHistory.length,
              itemBuilder: (context, index) {
                final msg = _chatHistory[index];
                final isUser = msg['role'] == 'user';

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppColors.primary
                          : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                        bottomLeft: !isUser ? Radius.zero : const Radius.circular(16),
                      ),
                      border: isUser
                          ? null
                          : Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      msg['content'] ?? '',
                      style: TextStyle(
                        color: isUser
                            ? Colors.white
                            : Theme.of(context).textTheme.bodyLarge?.color,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('AI Copilot is analyzing...',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    decoration: const InputDecoration(
                      hintText: 'Ask AI Copilot for help...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onSubmitted: (text) => _sendMessage(text),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                  onPressed: () => _sendMessage(_inputController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
