import 'package:flutter/cupertino.dart';

/// Lets code that lives above the Navigator (the root widget reacting to a
/// finished game) open screens such as the game-over summary.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
