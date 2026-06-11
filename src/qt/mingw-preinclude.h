/*
 * MinGW cross-compile preamble (included via -include for all GUI .cpp files).
 *
 * MXE GCC 11 defaults to GNU++17; Qt pulls <cstddef> which defines std::byte.
 * Windows SDK headers (rpcndr.h, objidl.h, ...) typedef unsigned char byte.
 * Force C++14 visibility before any system/Qt header is parsed.
 */
#ifndef INFINITERICKS_MINGW_PREINCLUDE_H
#define INFINITERICKS_MINGW_PREINCLUDE_H

#if defined(__MINGW32__) && defined(__cplusplus)
#if __cplusplus > 201402L
#undef __cplusplus
#define __cplusplus 201402L
#endif
#endif

#endif
