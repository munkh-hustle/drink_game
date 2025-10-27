import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'data/default_cards.dart';
import 'data/card_collections.dart';

void main() {
  runApp(DrinkingGameApp());
}

class DrinkingGameApp extends StatelessWidget {
  const DrinkingGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drinking Game',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  List<CardCollection> collections = List.from(defaultCollections);
  CardCollection? currentCollection;
  List<String> get currentCards => currentCollection?.cards ?? [];
  String currentCard = "Tap shuffle to start";
  final Random _random = Random();
  final String _storageKey = 'saved_collections';
  bool _isSwiping = false;

  // Timer variables
  int _timerSeconds = 5; // Default timer duration
  int _remainingSeconds = 0;
  bool _isTimerActive = false;
  late Timer _timer;

  // Rainbow colors
  final List<Color> _rainbowColors = [
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
  ];

  late AnimationController _colorAnimationController;
  int _currentColorIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadCollections();

    _colorAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Initialize timer
    _timer = Timer.periodic(const Duration(seconds: 1), _handleTimerTick);
  }

  @override
  void dispose() {
    _colorAnimationController.dispose();
    _timer.cancel();
    super.dispose();
  }

  void _handleTimerTick(Timer timer) {
    if (_isTimerActive && _remainingSeconds > 0) {
      setState(() {
        _remainingSeconds--;
      });
    } else if (_isTimerActive && _remainingSeconds <= 0) {
      setState(() {
        _isTimerActive = false;
      });
    }
  }

  void _startTimer() {
    setState(() {
      _remainingSeconds = _timerSeconds;
      _isTimerActive = true;
    });
  }

  void _stopTimer() {
    setState(() {
      _isTimerActive = false;
      _remainingSeconds = 0;
    });
  }

  void _setTimerDuration(int seconds) {
    setState(() {
      _timerSeconds = seconds;
    });
  }

  SharedPreferences? _prefs;

  Future<void> _loadCollections() async {
    _prefs ??= await SharedPreferences.getInstance();
    final savedCollections = _prefs!.getString(_storageKey);

    if (savedCollections != null) {
      final decoded = json.decode(savedCollections) as List<dynamic>;
      final loadedCollections =
          decoded
              .map(
                (item) => CardCollection(
                  id: item['id'],
                  name: item['name'],
                  cards: (item['cards'] as List<dynamic>).cast<String>(),
                  isDefault: item['isDefault'] ?? false,
                ),
              )
              .toList();

      setState(() {
        // Replace all collections with loaded ones
        collections = loadedCollections;
      });
    } else {
      setState(() {
        collections = List.from(defaultCollections);
      });
    }

    // Set default collection if none is selected
    if (currentCollection == null && collections.isNotEmpty) {
      setState(() {
        currentCollection = collections.first;
      });
    }
  }

  Future<void> _saveCollections() async {
    final prefs = await SharedPreferences.getInstance();
    // Save all collections (both default and custom)
    await prefs.setString(
      _storageKey,
      json.encode(collections.map((c) => c.toJson()).toList()),
    );
  }

  void _shuffleCard() {
    if (_isSwiping || currentCards.isEmpty) return;

    _animateColorChange();
    setState(() {
      currentCard = currentCards[_random.nextInt(currentCards.length)];
    });
    _startTimer();
  }

  void _animateColorChange() {
    setState(() {
      _currentColorIndex = (_currentColorIndex + 1) % _rainbowColors.length;
    });
    _colorAnimationController.reset();
    _colorAnimationController.forward();
  }

  void addNewCard(String newCard) {
    if (currentCollection == null) return;

    setState(() {
      final index = collections.indexWhere(
        (c) => c.id == currentCollection!.id, // Use ID instead of name
      );
      if (index != -1) {
        final updatedCollection = CardCollection(
          id: currentCollection!.id,
          name: currentCollection!.name,
          cards: [...currentCollection!.cards, newCard.trim()],
          isDefault: currentCollection!.isDefault,
        );

        collections[index] = updatedCollection;
        currentCollection = updatedCollection;
        _saveCollections();
      }
    });
  }

  void updateCard(int cardIndex, String newCardText) {
    if (currentCollection == null) return;

    setState(() {
      final index = collections.indexWhere(
        (c) => c.id == currentCollection!.id, // Use ID instead of name
      );
      if (index != -1) {
        final updatedCards = List<String>.from(currentCollection!.cards);
        updatedCards[cardIndex] = newCardText.trim();

        final updatedCollection = CardCollection(
          id: currentCollection!.id,
          name: currentCollection!.name,
          cards: updatedCards,
          isDefault: currentCollection!.isDefault,
        );

        collections[index] = updatedCollection;
        currentCollection = updatedCollection;

        // Update current card if it was the edited one
        if (currentCard == currentCollection!.cards[cardIndex]) {
          currentCard = newCardText.trim();
        }

        _saveCollections();
      }
    });
  }

  void deleteCard(int cardIndex) {
    if (currentCollection == null) return;

    setState(() {
      final index = collections.indexWhere(
        (c) => c.id == currentCollection!.id, // Use ID instead of name
      );
      if (index != -1) {
        final updatedCards = List<String>.from(currentCollection!.cards);
        final deletedCard = updatedCards.removeAt(cardIndex);

        final updatedCollection = CardCollection(
          id: currentCollection!.id,
          name: currentCollection!.name,
          cards: updatedCards,
          isDefault: currentCollection!.isDefault,
        );

        collections[index] = updatedCollection;
        currentCollection = updatedCollection;

        // Update current card if it was the deleted one
        if (currentCard == deletedCard && updatedCards.isNotEmpty) {
          _animateColorChange();
          currentCard = updatedCards[_random.nextInt(updatedCards.length)];
        } else if (updatedCards.isEmpty) {
          currentCard = "Collection is empty\nAdd some cards!";
        }

        _saveCollections();
      }
    });
  }

  void addNewCollection(String collectionName) {
    setState(() {
      final newCollection = CardCollection(
        name: collectionName,
        cards: [],
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}', // Unique ID
      );
      collections.add(newCollection);
      currentCollection = collections.last;
      _saveCollections();
    });
  }

  Widget _buildNeonCard(BuildContext context, String text) {
    return RepaintBoundary(
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          if (details.delta.dx > 0) {
            _handleSwipeRight();
          } else if (details.delta.dx < 0) {
            _handleSwipeLeft();
          }
        },
        child: AnimatedBuilder(
          animation: _colorAnimationController,
          builder: (context, child) {
            final currentColor = _rainbowColors[_currentColorIndex];
            final nextColorIndex =
                (_currentColorIndex + 1) % _rainbowColors.length;
            final nextColor = _rainbowColors[nextColorIndex];

            final animatedColor =
                Color.lerp(
                  currentColor,
                  nextColor,
                  _colorAnimationController.value,
                )!;

            return Container(
              width: 320,
              height: 450,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: animatedColor.withOpacity(0.8),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: _getComplementaryColor(
                      animatedColor,
                    ).withOpacity(0.6),
                    blurRadius: 30,
                    spreadRadius: 1,
                  ),
                ],
                border: Border.all(color: animatedColor, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.pinkAccent[100],
                      shadows: [Shadow(blurRadius: 10, color: animatedColor)],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _getComplementaryColor(Color color) {
    // Get a complementary color by rotating hue by 180 degrees
    final hsl = HSLColor.fromColor(color);
    return hsl.withHue((hsl.hue + 180) % 360).toColor();
  }

  void _handleSwipeLeft() {
    if (_isSwiping || currentCards.isEmpty) return;
    _isSwiping = true;

    Future.microtask(() {
      _animateColorChange();
      setState(() {
        currentCard = currentCards[_random.nextInt(currentCards.length)];
      });
      _startTimer();
      Future.delayed(const Duration(milliseconds: 300), () {
        _isSwiping = false;
      });
    });
  }

  void _handleSwipeRight() {
    if (_isSwiping || currentCards.isEmpty) return;
    _isSwiping = true;

    Future.microtask(() {
      _animateColorChange();
      setState(() {
        currentCard = currentCards[_random.nextInt(currentCards.length)];
      });
      _startTimer();
      Future.delayed(const Duration(milliseconds: 300), () {
        _isSwiping = false;
      });
    });
  }

  void _selectCollection(CardCollection collection) {
    setState(() {
      currentCollection = collection;
      if (collection.cards.isNotEmpty) {
        _animateColorChange();
        currentCard =
            collection.cards[_random.nextInt(collection.cards.length)];
      } else {
        currentCard = "Collection is empty\nAdd some cards!";
      }
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Drinking Game'),
            if (currentCollection != null)
              Text(
                currentCollection!.name,
                style: TextStyle(fontSize: 12, color: Colors.purple[300]),
              ),
          ],
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.pinkAccent[100],
        actions: [
          // Timer settings button
          PopupMenuButton<int>(
            icon: Icon(
              Icons.timer,
              color:
                  _isTimerActive ? Colors.greenAccent : Colors.pinkAccent[100],
            ),
            onSelected: (value) {
              _setTimerDuration(value);
            },
            itemBuilder:
                (BuildContext context) => [
                  PopupMenuItem(
                    value: 5,
                    child: Row(
                      children: [
                        Icon(Icons.timer, color: Colors.purpleAccent),
                        SizedBox(width: 8),
                        Text('5 Seconds'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 10,
                    child: Row(
                      children: [
                        Icon(Icons.timer, color: Colors.blueAccent),
                        SizedBox(width: 8),
                        Text('10 Seconds'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 15,
                    child: Row(
                      children: [
                        Icon(Icons.timer, color: Colors.greenAccent),
                        SizedBox(width: 8),
                        Text('15 Seconds'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 30,
                    child: Row(
                      children: [
                        Icon(Icons.timer, color: Colors.orangeAccent),
                        SizedBox(width: 8),
                        Text('30 Seconds'),
                      ],
                    ),
                  ),
                ],
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => _showAllCards(context),
          ),
          IconButton(
            icon: const Icon(Icons.collections),
            onPressed: () => _showCollectionSelector(context),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [Colors.purple.withOpacity(0.1), Colors.black],
            radius: 1.5,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Timer display
              if (_isTimerActive)
                Container(
                  margin: EdgeInsets.only(bottom: 20),
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.greenAccent, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.greenAccent.withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer, color: Colors.greenAccent, size: 20),
                      SizedBox(width: 8),
                      Text(
                        '$_remainingSeconds',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'seconds',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              else if (!_isTimerActive &&
                  _remainingSeconds == 0 &&
                  currentCards.isNotEmpty)
                Container(
                  margin: EdgeInsets.only(bottom: 20),
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.purpleAccent, width: 1),
                  ),
                  child: Text(
                    'Swipe to start timer',
                    style: TextStyle(color: Colors.purpleAccent, fontSize: 16),
                  ),
                ),

              // Collection info
              if (currentCollection != null)
                Text(
                  '${currentCollection!.cards.length} cards in collection',
                  style: TextStyle(color: Colors.purple[300], fontSize: 14),
                ),

              // Swipe instructions
              Text(
                'Swipe left or right to shuffle',
                style: TextStyle(color: Colors.purple[300], fontSize: 16),
              ),
              const SizedBox(height: 20),

              // Animated card
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: _buildNeonCard(context, currentCard),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAllCards(BuildContext context) async {
    if (currentCollection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a collection first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'All Cards in ${currentCollection!.name}',
                      style: TextStyle(
                        color: Colors.pinkAccent[100],
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${currentCollection!.cards.length} cards',
                      style: TextStyle(color: Colors.purple[300], fontSize: 14),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.purpleAccent),
              // Add New Card button at the top
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Card(
                  color: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.greenAccent, width: 2),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.withOpacity(0.3),
                      child: Icon(
                        Icons.add,
                        color: Colors.greenAccent,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      'Add New Card',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward,
                      color: Colors.greenAccent,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showAddCardDialog(context);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: currentCollection!.cards.length,
                  itemBuilder: (context, index) {
                    final card = currentCollection!.cards[index];
                    return Card(
                      color: Colors.black,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color:
                              currentCard == card
                                  ? Colors.pinkAccent
                                  : Colors.purpleAccent,
                          width: currentCard == card ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple.withOpacity(0.3),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: Colors.pinkAccent[100],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          card,
                          style: TextStyle(
                            color: Colors.pinkAccent[100],
                            fontSize: 16,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (currentCard == card)
                              Icon(
                                Icons.star,
                                color: Colors.pinkAccent,
                                size: 20,
                              ),
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                color: Colors.purple[300],
                              ),
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showEditCardDialog(context, index, card);
                                } else if (value == 'delete') {
                                  _showDeleteCardDialog(context, index, card);
                                } else if (value == 'set_current') {
                                  setState(() {
                                    currentCard = card;
                                  });
                                  Navigator.of(context).pop();
                                }
                              },
                              itemBuilder:
                                  (BuildContext context) => [
                                    PopupMenuItem(
                                      value: 'set_current',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.star,
                                            color: Colors.purpleAccent,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Set as Current'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.edit,
                                            color: Colors.blueAccent,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Edit Card'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete,
                                            color: Colors.redAccent,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Delete Card'),
                                        ],
                                      ),
                                    ),
                                  ],
                            ),
                          ],
                        ),
                        onTap: () {
                          setState(() {
                            currentCard = card;
                          });
                          Navigator.of(context).pop();
                        },
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.withOpacity(0.3),
                    foregroundColor: Colors.pinkAccent[100],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.purpleAccent),
                    ),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditCardDialog(
    BuildContext context,
    int cardIndex,
    String currentText,
  ) async {
    String editedCard = currentText;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.purpleAccent, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Edit Card',
                  style: TextStyle(
                    color: Colors.pinkAccent[100],
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (value) => editedCard = value,
                  controller: TextEditingController(text: currentText),
                  decoration: InputDecoration(
                    hintText: "Enter card text",
                    hintStyle: TextStyle(color: Colors.purple[300]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.purpleAccent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.pinkAccent),
                    ),
                  ),
                  style: TextStyle(color: Colors.pinkAccent[100]),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: Colors.purple[300]),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      child: Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.pinkAccent[100],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        if (editedCard.trim().isNotEmpty) {
                          updateCard(cardIndex, editedCard.trim());
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDeleteCardDialog(
    BuildContext context,
    int cardIndex,
    String cardText,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: Text(
            'Delete Card',
            style: TextStyle(color: Colors.pinkAccent[100]),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this card?',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cardText.length > 100
                      ? '${cardText.substring(0, 100)}...'
                      : cardText,
                  style: TextStyle(color: Colors.purple[300], fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.purple[300]),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                deleteCard(cardIndex);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddCardDialog(BuildContext context) async {
    String newCard = '';
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.purpleAccent, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add Card to ${currentCollection!.name}',
                  style: TextStyle(
                    color: Colors.pinkAccent[100],
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (value) => newCard = value,
                  decoration: InputDecoration(
                    hintText: "Enter card text",
                    hintStyle: TextStyle(color: Colors.purple[300]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.purpleAccent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.pinkAccent),
                    ),
                  ),
                  style: TextStyle(color: Colors.pinkAccent[100]),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: Colors.purple[300]),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      child: Text(
                        'Add',
                        style: TextStyle(
                          color: Colors.pinkAccent[100],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        if (newCard.trim().isNotEmpty) {
                          addNewCard(newCard.trim());
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCollectionSelector(BuildContext context) async {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Card Collection',
                style: TextStyle(
                  color: Colors.pinkAccent[100],
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: collections.length + 1, // +1 for "Add New" button
                  itemBuilder: (context, index) {
                    if (index == collections.length) {
                      return ListTile(
                        leading: Icon(Icons.add, color: Colors.purpleAccent),
                        title: Text(
                          'Create New Collection',
                          style: TextStyle(color: Colors.purple[300]),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          _showAddCollectionDialog(context);
                        },
                      );
                    }

                    final collection = collections[index];
                    return ListTile(
                      leading: Icon(
                        Icons.collections,
                        color:
                            currentCollection?.name == collection.name
                                ? Colors.pinkAccent
                                : Colors.purpleAccent,
                      ),
                      title: Text(
                        collection.name,
                        style: TextStyle(
                          color:
                              currentCollection?.name == collection.name
                                  ? Colors.pinkAccent[100]
                                  : Colors.white,
                          fontWeight:
                              currentCollection?.name == collection.name
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${collection.cards.length} cards',
                        style: TextStyle(color: Colors.purple[300]),
                      ),
                      trailing:
                          collection.isDefault
                              ? null
                              : IconButton(
                                icon: Icon(
                                  Icons.delete,
                                  color: Colors.red[300],
                                ),
                                onPressed: () {
                                  _deleteCollection(collection, context);
                                },
                              ),
                      onTap: () => _selectCollection(collection),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _deleteCollection(CardCollection collection, BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: Text(
            'Delete Collection',
            style: TextStyle(color: Colors.pinkAccent[100]),
          ),
          content: Text(
            'Are you sure you want to delete "${collection.name}"?',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.purple[300]),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                setState(() {
                  collections.remove(collection);
                  if (currentCollection == collection) {
                    currentCollection =
                        collections.isNotEmpty ? collections.first : null;
                  }
                  _saveCollections();
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddCollectionDialog(BuildContext context) async {
    String collectionName = '';
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.purpleAccent, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Create New Collection',
                  style: TextStyle(
                    color: Colors.pinkAccent[100],
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (value) => collectionName = value,
                  decoration: InputDecoration(
                    hintText: "Enter collection name",
                    hintStyle: TextStyle(color: Colors.purple[300]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.purpleAccent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.pinkAccent),
                    ),
                  ),
                  style: TextStyle(color: Colors.pinkAccent[100]),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: Colors.purple[300]),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      child: Text(
                        'Create',
                        style: TextStyle(
                          color: Colors.pinkAccent[100],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        if (collectionName.trim().isNotEmpty) {
                          addNewCollection(collectionName.trim());
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
