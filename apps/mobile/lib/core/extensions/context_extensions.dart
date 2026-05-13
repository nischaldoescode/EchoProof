// build context extension methods
// provides shorthand access to theme, size, and navigation

import 'package:flutter/material.dart';
import '../utils/snack.dart';

extension ContextExtensions on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;
  bool get isTablet => MediaQuery.sizeOf(this).width > 700;
  bool get isPhone => MediaQuery.sizeOf(this).width <= 700;

  void showSnackbar(String message, {bool isError = false}) {
    if (isError) {
      showErrorSnack(this, message);
    } else {
      showInfoSnack(this, message);
    }
  }
}
