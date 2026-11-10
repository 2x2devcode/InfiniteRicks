#ifndef GUICONSTANTS_H
#define GUICONSTANTS_H

/* Milliseconds between model updates */
static const int MODEL_UPDATE_DELAY = 500;

/* AskPassphraseDialog -- Maximum passphrase length */
static const int MAX_PASSPHRASE_SIZE = 1024;

/* BitcoinGUI -- Size of icons in status bar */
static const int STATUSBAR_ICONSIZE = 16;

/* Invalid field background style */
#define STYLE_INVALID "background:#fde8e8;border:1px solid #f5b5b5;border-radius:4px"

/* Transaction list -- unconfirmed transaction */
#define COLOR_UNCONFIRMED QColor(118, 128, 144)
/* Transaction list -- negative amount */
#define COLOR_NEGATIVE QColor(239, 68, 68)
/* Transaction list -- positive confirmed amount */
#define COLOR_POSITIVE QColor(34, 197, 94)
/* Transaction list -- bare address (without label) */
#define COLOR_BAREADDRESS QColor(107, 114, 128)

/* Brand accent — Matrix green (RGB 94, 174, 76) */
#define COLOR_BRAND QColor(94, 174, 76)
#define COLOR_BRAND_DARK QColor(77, 154, 62)

/* Overview recent transactions — keep icons small to save memory while painting */
static const int OVERVIEW_TX_ICON_SIZE = 28;

/* Tooltips longer than this (in characters) are converted into rich text,
   so that they can be word-wrapped.
 */
static const int TOOLTIP_WRAP_THRESHOLD = 80;

/* Maximum allowed URI length */
static const int MAX_URI_LENGTH = 255;

/* QRCodeDialog -- size of exported QR Code image */
#define EXPORT_IMAGE_SIZE 256

#endif // GUICONSTANTS_H
