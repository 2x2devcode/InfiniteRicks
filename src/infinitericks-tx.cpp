// Copyright (c) 2009-2012 The Bitcoin developers
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "base58.h"
#include "txtools.h"

#include "util.h"
#include "version.h"
#include "json/json_spirit_utils.h"
#include "json/json_spirit_writer_template.h"

#include <boost/algorithm/string.hpp>
#include <boost/assign/list_of.hpp>

using namespace std;
using namespace boost;
using namespace boost::assign;
using namespace json_spirit;

extern void noui_connect();

static std::string HelpMessage()
{
    return std::string("InfiniteRicks-tx version ") + FormatFullVersion() + "\n"
        "\n"
        "Usage:\n"
        "  InfiniteRicks-tx [options] <hex-tx> [commands]\n"
        "  InfiniteRicks-tx -create [commands]\n"
        "\n"
        "Options:\n"
        "  -create            Create new, empty transaction\n"
        "  -json              Convert transaction to JSON\n"
        "  -combine           Combine multiple hex transactions\n"
        "\n"
        "Commands:\n"
        "  in=TXID:VOUT       Add input to transaction\n"
        "  outaddr=AMOUNT:ADDR Add output to transaction\n"
        "  nversion=NUM       Set transaction version\n"
        "  nlocktime=NUM      Set transaction lock time\n"
        "  delin=N            Delete input N\n"
        "  delout=N           Delete output N\n"
        "  signprevtxin=TXID:VOUT:SCRIPTPUBKEY  Register previous output script for signing\n"
        "  key=WIF            Add private key for signing\n"
        "  sighash=TYPE       Sighash type (ALL, NONE, SINGLE, ALL|ANYONECANPAY, ...)\n"
        "  sign               Sign transaction with registered keys and prevouts\n";
}

static bool ParseHash(const std::string& str, uint256& hash)
{
    if (!IsHex(str))
        return false;
    hash.SetHex(str);
    return true;
}

static bool ParseIn(const std::string& arg, uint256& hash, unsigned int& nOut)
{
    vector<string> parts;
    boost::split(parts, arg, boost::is_any_of(":"));
    if (parts.size() != 2)
        return false;
    if (!ParseHash(parts[0], hash))
        return false;
    nOut = atoi(parts[1].c_str());
    return true;
}

static bool ParseOutAddr(const std::string& arg, double& amount, std::string& address)
{
    vector<string> parts;
    boost::split(parts, arg, boost::is_any_of(":"));
    if (parts.size() != 2)
        return false;
    amount = atof(parts[0].c_str());
    address = parts[1];
    return true;
}

static bool ParseSignPrevTxIn(const std::string& arg, COutPoint& outpoint, CScript& scriptPubKey)
{
    vector<string> parts;
    boost::split(parts, arg, boost::is_any_of(":"));
    if (parts.size() != 3)
        return false;
    uint256 hash;
    if (!ParseHash(parts[0], hash))
        return false;
    outpoint = COutPoint(hash, atoi(parts[1].c_str()));
    if (!IsHex(parts[2]))
        return false;
    vector<unsigned char> pkData(ParseHex(parts[2]));
    scriptPubKey = CScript(pkData.begin(), pkData.end());
    return true;
}

static int ParseSighash(const std::string& strHashType)
{
    static map<string, int> mapSigHashValues =
        map_list_of
        (string("ALL"), int(SIGHASH_ALL))
        (string("ALL|ANYONECANPAY"), int(SIGHASH_ALL|SIGHASH_ANYONECANPAY))
        (string("NONE"), int(SIGHASH_NONE))
        (string("NONE|ANYONECANPAY"), int(SIGHASH_NONE|SIGHASH_ANYONECANPAY))
        (string("SINGLE"), int(SIGHASH_SINGLE))
        (string("SINGLE|ANYONECANPAY"), int(SIGHASH_SINGLE|SIGHASH_ANYONECANPAY));
    if (mapSigHashValues.count(strHashType))
        return mapSigHashValues[strHashType];
    throw runtime_error("Invalid sighash param");
}

int main(int argc, char* argv[])
{
    setbuf(stdin, NULL);
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    noui_connect();
    ParseParameters(argc, argv);

    if (mapArgs.count("-?") || mapArgs.count("-h") || mapArgs.count("-help") || argc < 2)
    {
        fprintf(stdout, "%s", HelpMessage().c_str());
        return argc < 2 ? 1 : 0;
    }

    bool fCreate = mapArgs.count("-create");
    bool fJson = mapArgs.count("-json");
    bool fCombine = mapArgs.count("-combine");
    bool fSign = false;

    vector<CTransaction> txVariants;
    vector<std::pair<uint256, unsigned int> > inputs;
    map<string, double> outputs;
    map<COutPoint, CScript> mapPrevOut;
    vector<string> keys;
    int nHashType = SIGHASH_ALL;

    for (int i = 1; i < argc; i++)
    {
        string arg = argv[i];
        if (IsSwitchChar(arg[0]))
            continue;

        if (fCreate || fCombine)
        {
            if (arg.find('=') != string::npos)
            {
                string name = arg.substr(0, arg.find('='));
                string value = arg.substr(arg.find('=') + 1);
                if (name == "in")
                {
                    uint256 hash;
                    unsigned int nOut;
                    if (!ParseIn(value, hash, nOut))
                        throw runtime_error("Invalid in= parameter");
                    inputs.push_back(make_pair(hash, nOut));
                }
                else if (name == "outaddr")
                {
                    double amount;
                    string address;
                    if (!ParseOutAddr(value, amount, address))
                        throw runtime_error("Invalid outaddr= parameter");
                    outputs[address] = amount;
                }
                else if (name == "signprevtxin")
                {
                    COutPoint outpoint;
                    CScript scriptPubKey;
                    if (!ParseSignPrevTxIn(value, outpoint, scriptPubKey))
                        throw runtime_error("Invalid signprevtxin= parameter");
                    mapPrevOut[outpoint] = scriptPubKey;
                }
                else if (name == "key")
                    keys.push_back(value);
                else if (name == "sighash")
                    nHashType = ParseSighash(value);
                else if (name == "nversion")
                {
                    if (txVariants.empty())
                        txVariants.push_back(CTransaction());
                    txVariants[0].nVersion = atoi(value.c_str());
                }
                else if (name == "nlocktime")
                {
                    if (txVariants.empty())
                        txVariants.push_back(CTransaction());
                    txVariants[0].nLockTime = atoi(value.c_str());
                }
                else if (name == "sign")
                    fSign = true;
                else
                    throw runtime_error(string("Unknown command: ") + name);
            }
            else if (fCombine && IsHex(arg))
            {
                CTransaction tx;
                string strError;
                if (!DecodeHexTx(tx, arg, strError))
                    throw runtime_error(strError);
                txVariants.push_back(tx);
            }
            else if (!fCreate)
                throw runtime_error(string("Unknown argument: ") + arg);
        }
        else
        {
            if (txVariants.empty() && IsHex(arg))
            {
                CTransaction tx;
                string strError;
                if (!DecodeHexTx(tx, arg, strError))
                    throw runtime_error(strError);
                txVariants.push_back(tx);
            }
            else if (arg.find('=') != string::npos)
            {
                string name = arg.substr(0, arg.find('='));
                string value = arg.substr(arg.find('=') + 1);
                if (name == "in")
                {
                    uint256 hash;
                    unsigned int nOut;
                    if (!ParseIn(value, hash, nOut))
                        throw runtime_error("Invalid in= parameter");
                    inputs.push_back(make_pair(hash, nOut));
                }
                else if (name == "outaddr")
                {
                    double amount;
                    string address;
                    if (!ParseOutAddr(value, amount, address))
                        throw runtime_error("Invalid outaddr= parameter");
                    outputs[address] = amount;
                }
                else if (name == "delin")
                {
                    unsigned int n = atoi(value.c_str());
                    if (txVariants.empty() || n >= txVariants[0].vin.size())
                        throw runtime_error("Invalid delin index");
                    txVariants[0].vin.erase(txVariants[0].vin.begin() + n);
                }
                else if (name == "delout")
                {
                    unsigned int n = atoi(value.c_str());
                    if (txVariants.empty() || n >= txVariants[0].vout.size())
                        throw runtime_error("Invalid delout index");
                    txVariants[0].vout.erase(txVariants[0].vout.begin() + n);
                }
                else if (name == "nversion")
                {
                    if (txVariants.empty())
                        throw runtime_error("Missing transaction");
                    txVariants[0].nVersion = atoi(value.c_str());
                }
                else if (name == "nlocktime")
                {
                    if (txVariants.empty())
                        throw runtime_error("Missing transaction");
                    txVariants[0].nLockTime = atoi(value.c_str());
                }
                else if (name == "signprevtxin")
                {
                    COutPoint outpoint;
                    CScript scriptPubKey;
                    if (!ParseSignPrevTxIn(value, outpoint, scriptPubKey))
                        throw runtime_error("Invalid signprevtxin= parameter");
                    mapPrevOut[outpoint] = scriptPubKey;
                }
                else if (name == "key")
                    keys.push_back(value);
                else if (name == "sighash")
                    nHashType = ParseSighash(value);
                else if (name == "sign")
                    fSign = true;
                else
                    throw runtime_error(string("Unknown command: ") + name);
            }
            else
                throw runtime_error(string("Unknown argument: ") + arg);
        }
    }

    try
    {
        CTransaction tx;
        if (fCreate)
        {
            if (!inputs.empty() || !outputs.empty())
                txVariants.push_back(CTransaction());
            if (!inputs.empty() || !outputs.empty())
            {
                string hex = CreateRawTx(inputs, outputs);
                string strError;
                if (!DecodeHexTx(tx, hex, strError))
                    throw runtime_error(strError);
            }
            else if (!txVariants.empty())
                tx = txVariants[0];
            else
                tx = CTransaction();
        }
        else if (fCombine)
        {
            if (txVariants.size() < 2)
                throw runtime_error("combine requires at least two transactions");
            tx = CombineTransactions(txVariants, mapPrevOut);
        }
        else
        {
            if (txVariants.empty())
                throw runtime_error("Missing transaction hex");
            tx = txVariants[0];

            if (!inputs.empty() || !outputs.empty())
            {
                for (size_t i = 0; i < inputs.size(); i++)
                    tx.vin.push_back(CTxIn(COutPoint(inputs[i].first, inputs[i].second)));
                for (map<string, double>::const_iterator it = outputs.begin(); it != outputs.end(); ++it)
                {
                    CBitcoinAddress address(it->first);
                    if (!address.IsValid())
                        throw runtime_error(string("Invalid address: ") + it->first);
                    CScript scriptPubKey;
                    scriptPubKey.SetDestination(address.Get());
                    int64_t nAmount = roundint64(it->second * COIN);
                    tx.vout.push_back(CTxOut(nAmount, scriptPubKey));
                }
            }
        }

        if (fSign && !keys.empty())
        {
            bool fComplete = false;
            SignTxWithKeys(tx, mapPrevOut, keys, nHashType, fComplete);
        }

        if (fJson)
        {
            Object o = DecodeTxToJSON(tx);
            fprintf(stdout, "%s\n", write_string(Value(o), true).c_str());
        }
        else
        {
            fprintf(stdout, "%s\n", EncodeHexTx(tx).c_str());
        }
        return 0;
    }
    catch (std::exception& e)
    {
        fprintf(stderr, "error: %s\n", e.what());
        return 1;
    }
}
