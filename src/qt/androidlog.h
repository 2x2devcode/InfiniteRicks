#ifndef BITCOIN_QT_ANDROIDLOG_H
#define BITCOIN_QT_ANDROIDLOG_H

#if defined(__ANDROID__)
#include <android/log.h>
#define IR_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "InfiniteRicks", __VA_ARGS__)
#define IR_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "InfiniteRicks", __VA_ARGS__)
#else
#define IR_LOGI(...) do { } while (0)
#define IR_LOGE(...) do { } while (0)
#endif

#endif // BITCOIN_QT_ANDROIDLOG_H
