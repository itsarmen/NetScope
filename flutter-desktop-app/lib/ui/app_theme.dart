/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:flutter/material.dart';

// Compile-time aliases kept for brevity in widgets.
const kAccent = AppColors.accent;
const kSuccess = AppColors.success;
const kInfo = AppColors.info;
const kWarning = AppColors.warning;
const kError = AppColors.error;

/// Central color tokens (prompt 02 section 3 + prompt 03 softened borders).
class AppColors {
  static const accent = Color(0xFFE95420);
  static const accentDark = Color(0xFFC8431B);

  static const surface = Color(0xFFFFFFFF);

  static const success = Color(0xFF0E8420);
  static const info = Color(0xFF1C71D8);
  static const warning = Color(0xFFC64600);
  static const purple = Color(0xFF7B3FA0);
  static const error = Color(0xFFC01C28);

  static const text = Color(0xFF2B2B2B);
  static const secondary = Color(0xFF6B6B6B);
  static const placeholder = Color(0xFF8A8A8A);
  static const disabled = Color(0xFFB0B0B0);

  // Borders (prompt 03: light and soft).
  static const border = Color(0xFFE8E8E8);
  static const divider = Color(0xFFEFEFEF);
  static const dividerTable = Color(0xFFEEEEEE);
  static const borderField = Color(0xFFDCDCDC);
  static const borderHover = Color(0xFFC8C8C8);
  static const borderSelected = Color(0xFFBDBDBD);
  static const borderOuter = Color(0xFFE0E0E0);
  static const checkboxBorder = Color(0xFF8A8A8A);

  static const selection = Color(0xFFCFE3FF);
  static const scrollbar = Color(0xFFC8C8C8);
  static const scrollbarHover = Color(0xFFA8A8A8);
  static const tooltipBg = Color(0xFF2B2B2B);

  // Dark-mode equivalents.
  static const darkBorder = Color(0xFF3A3A3A);
  static const darkDivider = Color(0xFF333333);
  static const darkBorderField = Color(0xFF484848);
  static const darkBorderHover = Color(0xFF5A5A5A);
  static const darkBorderSelected = Color(0xFF9E9E9E);
}

/// Central size tokens (prompt 03 component sizes).
class AppSizes {
  static const header = 48.0;
  static const sideRow = 40.0;
  static const sideRowIcon = 20.0;
  static const sideRowGap = 12.0;
  static const sideRowPad = 12.0;

  static const field = 36.0;
  static const button = 32.0;
  static const iconButton = 32.0;
  static const iconButtonIcon = 18.0;
  static const popupIconButton = 28.0;
  static const popupIconButtonIcon = 16.0;

  static const pill = 28.0;
  static const listRow = 56.0;
  static const popupTab = 40.0;
  static const popupHeader = 52.0;

  static const badgeH = 22.0;
  static const badgeMethodW = 52.0;
  static const badgeStatusW = 44.0;
  static const countBadgeH = 20.0;
  static const countBadgeMinW = 24.0;

  // Network table metrics (Part 1).
  static const tableRow = 32.0;
  static const columnHeader = 32.0;
  static const toolbar = 44.0;
  static const cardFooter = 36.0;
  static const domainMin = 140.0;
  static const fileMin = 220.0;

  static const radius = 8.0;
  static const radiusBadge = 6.0;
  static const radiusCount = 10.0;
  static const radiusPopup = 10.0;

  static const sidebarMin = 260.0;
  static const sidebarMax = 340.0;

  static const fontBody = 14.0;
  static const fontSecondary = 12.0;
  static const fontBadge = 11.0;
  static const fontTitle = 15.0;
  static const fontMono = 13.0;
  static const fontRowLabel = 14.0;
  static const fontSection = 12.0;
}
