// Copyright (c) 2009-2012 The Bitcoin developers
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_RPCCLIENT_H
#define BITCOIN_RPCCLIENT_H

#include <string>
#include <vector>

#include "json/json_spirit_value.h"

/** Send a JSON-RPC command to a running InfiniteRicksd instance. */
json_spirit::Object CallRPC(const std::string& strMethod, const json_spirit::Array& params);

/** Convert parameter values for RPC call from strings to command-specific JSON objects. */
json_spirit::Array RPCConvertValues(const std::string &strMethod, const std::vector<std::string> &strParams);

/** Parse argv and execute one RPC call against the configured server. */
int CommandLineRPC(int argc, char *argv[]);

#endif
