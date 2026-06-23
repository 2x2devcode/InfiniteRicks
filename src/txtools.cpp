// Copyright (c) 2009-2012 The Bitcoin developers
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "txtools.h"

#include "base58.h"
#include "keystore.h"
#include "script.h"
#include "util.h"

#include <boost/assign/list_of.hpp>
#include <boost/foreach.hpp>
#include <set>

using namespace std;
using namespace boost;
using namespace boost::assign;
using namespace json_spirit;

static void ScriptPubKeyToJSON(const CScript& scriptPubKey, Object& out, bool fIncludeHex)
{
    txnouttype type;
    vector<CTxDestination> addresses;
    int nRequired;

    out.push_back(Pair("asm", scriptPubKey.ToString()));

    if (fIncludeHex)
        out.push_back(Pair("hex", HexStr(scriptPubKey.begin(), scriptPubKey.end())));

    if (!ExtractDestinations(scriptPubKey, type, addresses, nRequired))
    {
        out.push_back(Pair("type", GetTxnOutputType(type)));
        return;
    }

    out.push_back(Pair("reqSigs", nRequired));
    out.push_back(Pair("type", GetTxnOutputType(type)));

    Array a;
    BOOST_FOREACH(const CTxDestination& addr, addresses)
        a.push_back(CBitcoinAddress(addr).ToString());
    out.push_back(Pair("addresses", a));
}

static void TxToJSON(const CTransaction& tx, Object& entry)
{
    entry.push_back(Pair("txid", tx.GetHash().GetHex()));
    entry.push_back(Pair("version", tx.nVersion));
    entry.push_back(Pair("time", (int64_t)tx.nTime));
    entry.push_back(Pair("locktime", (int64_t)tx.nLockTime));
    Array vin;
    BOOST_FOREACH(const CTxIn& txin, tx.vin)
    {
        Object in;
        if (tx.IsCoinBase())
            in.push_back(Pair("coinbase", HexStr(txin.scriptSig.begin(), txin.scriptSig.end())));
        else
        {
            in.push_back(Pair("txid", txin.prevout.hash.GetHex()));
            in.push_back(Pair("vout", (int64_t)txin.prevout.n));
            Object o;
            o.push_back(Pair("asm", txin.scriptSig.ToString()));
            o.push_back(Pair("hex", HexStr(txin.scriptSig.begin(), txin.scriptSig.end())));
            in.push_back(Pair("scriptSig", o));
        }
        in.push_back(Pair("sequence", (int64_t)txin.nSequence));
        vin.push_back(in);
    }
    entry.push_back(Pair("vin", vin));
    Array vout;
    for (unsigned int i = 0; i < tx.vout.size(); i++)
    {
        const CTxOut& txout = tx.vout[i];
        Object out;
        out.push_back(Pair("value", (double)txout.nValue / (double)COIN));
        out.push_back(Pair("n", (int64_t)i));
        Object o;
        ScriptPubKeyToJSON(txout.scriptPubKey, o, false);
        out.push_back(Pair("scriptPubKey", o));
        vout.push_back(out);
    }
    entry.push_back(Pair("vout", vout));
}

std::string EncodeHexTx(const CTransaction& tx)
{
    CDataStream ss(SER_NETWORK, PROTOCOL_VERSION);
    ss << tx;
    return HexStr(ss.begin(), ss.end());
}

bool DecodeHexTx(CTransaction& tx, const std::string& strHex, std::string& strError)
{
    vector<unsigned char> txData(ParseHex(strHex));
    CDataStream ssData(txData, SER_NETWORK, PROTOCOL_VERSION);
    try {
        ssData >> tx;
    }
    catch (std::exception &e) {
        strError = "TX decode failed";
        return false;
    }
    return true;
}

std::string CreateRawTx(const std::vector<std::pair<uint256, unsigned int> >& inputs,
                        const std::map<std::string, double>& outputs)
{
    CTransaction rawTx;

    for (size_t i = 0; i < inputs.size(); i++)
    {
        const std::pair<uint256, unsigned int>& input = inputs[i];
        CTxIn in(COutPoint(input.first, input.second));
        rawTx.vin.push_back(in);
    }

    set<CBitcoinAddress> setAddress;
    for (map<string, double>::const_iterator it = outputs.begin(); it != outputs.end(); ++it)
    {
        const string& addressName = it->first;
        double amount = it->second;
        CBitcoinAddress address(addressName);
        if (!address.IsValid())
            throw runtime_error(string("Invalid InfiniteRicks address: ") + addressName);

        if (setAddress.count(address))
            throw runtime_error(string("Duplicated address: ") + addressName);
        setAddress.insert(address);

        CScript scriptPubKey;
        scriptPubKey.SetDestination(address.Get());
        int64_t nAmount = roundint64(amount * COIN);
        if (!MoneyRange(nAmount))
            throw runtime_error("Invalid amount");

        CTxOut out(nAmount, scriptPubKey);
        rawTx.vout.push_back(out);
    }

    return EncodeHexTx(rawTx);
}

Object DecodeTxToJSON(const CTransaction& tx)
{
    Object result;
    TxToJSON(tx, result);
    return result;
}

CTransaction CombineTransactions(const std::vector<CTransaction>& txVariants,
                                 const std::map<COutPoint, CScript>& mapPrevOut)
{
    if (txVariants.empty())
        throw runtime_error("Missing transaction");

    CTransaction mergedTx(txVariants[0]);
    for (unsigned int i = 0; i < mergedTx.vin.size(); i++)
    {
        CTxIn& txin = mergedTx.vin[i];
        if (mapPrevOut.count(txin.prevout) == 0)
            continue;
        const CScript& prevPubKey = mapPrevOut.find(txin.prevout)->second;

        BOOST_FOREACH(const CTransaction& txv, txVariants)
        {
            if (i < txv.vin.size())
                txin.scriptSig = CombineSignatures(prevPubKey, mergedTx, i, txin.scriptSig, txv.vin[i].scriptSig);
        }
    }
    return mergedTx;
}

bool SignTxWithKeys(CTransaction& tx,
                    const std::map<COutPoint, CScript>& mapPrevOut,
                    const std::vector<std::string>& keys,
                    int nHashType,
                    bool& fComplete)
{
    fComplete = true;
    CBasicKeyStore keystore;
    BOOST_FOREACH(const std::string& keyStr, keys)
    {
        CBitcoinSecret vchSecret;
        if (!vchSecret.SetString(keyStr))
            throw runtime_error("Invalid private key");
        CKey key;
        bool fCompressed;
        CSecret secret = vchSecret.GetSecret(fCompressed);
        key.SetSecret(secret, fCompressed);
        keystore.AddKey(key);
    }

    bool fHashSingle = ((nHashType & ~SIGHASH_ANYONECANPAY) == SIGHASH_SINGLE);
    for (unsigned int i = 0; i < tx.vin.size(); i++)
    {
        CTxIn& txin = tx.vin[i];
        if (mapPrevOut.count(txin.prevout) == 0)
        {
            fComplete = false;
            continue;
        }
        const CScript& prevPubKey = mapPrevOut.find(txin.prevout)->second;
        txin.scriptSig.clear();
        if (!fHashSingle || (i < tx.vout.size()))
            SignSignature(keystore, prevPubKey, tx, i, nHashType);
        if (!VerifyScript(txin.scriptSig, prevPubKey, tx, i, 0))
            fComplete = false;
    }
    return true;
}
