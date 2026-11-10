// Copyright (c) 2009-2012 The Bitcoin developers
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_TXTOOLS_H
#define BITCOIN_TXTOOLS_H

#include <string>
#include <vector>
#include <map>

#include "json/json_spirit_value.h"
#include "main.h"

std::string EncodeHexTx(const CTransaction& tx);
bool DecodeHexTx(CTransaction& tx, const std::string& strHex, std::string& strError);
std::string CreateRawTx(const std::vector<std::pair<uint256, unsigned int> >& inputs,
                        const std::map<std::string, double>& outputs);
json_spirit::Object DecodeTxToJSON(const CTransaction& tx);
CTransaction CombineTransactions(const std::vector<CTransaction>& txVariants,
                                 const std::map<COutPoint, CScript>& mapPrevOut);
bool SignTxWithKeys(CTransaction& tx,
                    const std::map<COutPoint, CScript>& mapPrevOut,
                    const std::vector<std::string>& keys,
                    int nHashType,
                    bool& fComplete);

#endif
