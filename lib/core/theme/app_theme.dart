import 'package:flutter/material.dart';

import 'app_colors.dart';

ThemeData buildAppTheme() => ThemeData(
  useMaterial3: false,
  fontFamily: 'Arial',
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 14, color: AppColors.text),
  ),
  inputDecorationTheme: InputDecorationTheme(
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(7)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: const BorderSide(color: AppColors.inputBorder),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: const BorderSide(color: AppColors.inputBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: const BorderSide(color: AppColors.green),
    ),
    hintStyle: const TextStyle(color: Color(0xff9ca5aa), fontSize: 14),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.green,
      textStyle: const TextStyle(
        fontFamily: 'Arial',
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      minimumSize: const Size(0, 0),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
  ),
);
