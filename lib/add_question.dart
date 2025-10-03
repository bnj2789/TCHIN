import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/services.dart';

/// ---------------------------------------------------------------------------
///  ADD‑QUESTION SHEET  – glassmorphic card pops from bottom
/// ---------------------------------------------------------------------------
class AddQuestionPage extends StatefulWidget {
  const AddQuestionPage({super.key});

  @override
  State<AddQuestionPage> createState() => _AddQuestionPageState();
}

class _AddQuestionPageState extends State<AddQuestionPage> {
  final List<String> _questions = [];
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  void _loadQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('custom_questions') ?? [];
    setState(() => _questions.addAll(saved));
  }

  void _saveQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_questions', _questions);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Ajout inline (champ + bouton "+")
  void _handleInlineAdd() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _questions.add(text);
      _controller.clear();
    });
    _saveQuestions();
    HapticFeedback.selectionClick();
  }

  Widget _buildInlineComposerBar() {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 60,
              child: TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                minLines: 1,
                maxLines: 1,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\n')),
                ],
                maxLength: 69,
                buildCounter: (_, {required currentLength, required isFocused, required maxLength}) => null,
                decoration: InputDecoration(
                  hintText: t.addQuestionHint, // "Enter your question"
                  hintStyle: const TextStyle(color: Color.fromARGB(185, 255, 255, 255)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                  filled: true,
                  fillColor: Colors.black,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.25), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                    borderSide: const BorderSide(color: Color.fromARGB(210, 255, 255, 255), width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _handleInlineAdd(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: SizedBox(
              width: 60,
              height: 60,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black,
                  side: const BorderSide(color: Colors.white),
                  shape: const CircleBorder(),
                  minimumSize: const Size(60, 60),
                  fixedSize: const Size(60, 60),
                  padding: EdgeInsets.zero,
                ),
                onPressed: _handleInlineAdd,
                child: const Text(
                  '+',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //                                UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Garde la hauteur de la modale fixe quand le clavier apparaît
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // --- TAP OUTSIDE TO CLOSE ---
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.transparent),
            ),
          ),

          // --- DRAGGABLE GLASS CARD (95 % height) ---
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              // Si l'utilisateur tire vers le bas de 12 px ou +
              onVerticalDragUpdate: (details) {
                if (details.delta.dy > 12) {
                  Navigator.of(context).pop();
                }
              },
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.95,
                width: double.infinity,
                child: _buildGlassCard(theme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard(ThemeData theme) {
    final t = AppLocalizations.of(context)!;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom; // hauteur clavier
    final safeBottom = MediaQuery.of(context).padding.bottom;

    // La barre d'ajout est en overlay et remonte au-dessus du clavier
    final double composerBottomPad = (viewInsets > 0 ? viewInsets : safeBottom) + 12;

    // On NE repousse pas la liste de la hauteur du champ ; seulement du clavier
    final double listBottomPadding = (viewInsets > 0 ? viewInsets + 12 : 12);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: Colors.black.withOpacity(.5),
          ),
          child: Stack(
            children: [
              // --- Contenu principal (drag bar, header, liste) : la liste peut passer "sous" les overlays
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // drag bar
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Header: Close + Titre ("Add question") sur la même ligne
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          _buildCloseButton(),
                          Expanded(
                            child: Center(
                              child: Text(
                                t.addQuestionButton, // ex. "Add question"
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          // Espace factice pour centrer visuellement (taille du bouton Close)
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // LISTE de questions — passe "derrière" la barre d'ajout (overlay)
                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, listBottomPadding),
                      itemCount: _questions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      itemBuilder: (context, index) {
                        final text = _questions[index];
                        return _QuestionTile(
                          text: text,
                          onDelete: () {
                            setState(() => _questions.removeAt(index));
                            _saveQuestions();
                          },
                          onEdit: (newValue) {
                            setState(() => _questions[index] = newValue);
                            _saveQuestions();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),

              // --- Barre d'ajout en overlay : remonte au-dessus du clavier
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.only(bottom: composerBottomPad),
                  child: _buildInlineComposerBar(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.10), // léger fond
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: const Center(
          child: Icon(Icons.close, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
///  SINGLE QUESTION TILE
/// ---------------------------------------------------------------------------
class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.text,
    required this.onDelete,
    required this.onEdit,
  });

  final String text;
  final VoidCallback onDelete;
  final void Function(String) onEdit;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              width: 1,
              color: Colors.white.withOpacity(.22),
            ),
          ),
          child: GestureDetector(
            onTap: () async {
              // On conserve la popup pour EDITER
              final updated = await showDialog<String>(
                context: context,
                builder: (_) => _AddQuestionDialog(
                  controller: TextEditingController(text: text),
                  isEditing: true,
                ),
              );
              if (updated != null && updated.trim().isNotEmpty && updated.trim() != text) {
                onEdit(updated.trim());
              }
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    softWrap: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white70),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
///  ADD QUESTION DIALOG (pour l'édition uniquement)
/// ---------------------------------------------------------------------------
class _AddQuestionDialog extends StatelessWidget {
  const _AddQuestionDialog({required this.controller, required this.isEditing});

  final TextEditingController controller;
  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEditing ? t.editQuestionTitle : t.addQuestionTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 24),
                  minLines: 1,
                  maxLines: null, // allow automatic wrapping
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\n')), // block manual line breaks
                  ],
                  maxLength: 69,
                  buildCounter: (_, {required currentLength, required isFocused, required maxLength}) => null,
                  decoration: InputDecoration(
                    hintText: t.addQuestionHint,
                    hintStyle: const TextStyle(color: Colors.white54),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white70),
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white38),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Column(
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        fixedSize: const Size(160, 48),
                      ),
                      onPressed: () {
                        final text = controller.text.trim();
                        if (text.isNotEmpty) {
                          Navigator.of(context).pop(text);
                        }
                      },
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          t.save,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Text(
                        t.cancel,
                        style: const TextStyle(color: Colors.white70, fontSize: 18),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}