// Copyright (c) 2009-2012 The Bitcoin developers
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "util.h"
#include "rpcclient.h"

extern void noui_connect();

static std::string HelpMessage()
{
    return std::string("InfiniteRicks-cli version ") + FormatFullVersion() + "\n"
        "\n"
        "Usage:\n"
        "  InfiniteRicks-cli [options] <command> [params]  Send command to InfiniteRicksd\n"
        "  InfiniteRicks-cli [options] help                List commands\n"
        "  InfiniteRicks-cli [options] help <command>      Get help for a command\n"
        "\n"
        "Options:\n"
        "  -conf=<file>      Specify configuration file (default: InfiniteRicks.conf)\n"
        "  -datadir=<dir>    Specify data directory\n"
        "  -rpcconnect=<ip>  Send commands to node running on <ip> (default: 127.0.0.1)\n"
        "  -rpcport=<port>   Connect to JSON-RPC on <port> (default: 31648 or testnet: 41648)\n"
        "  -rpcuser=<user>   Username for JSON-RPC connections\n"
        "  -rpcpassword=<pw> Password for JSON-RPC connections\n"
        "  -rpcssl           Use OpenSSL and connect to https:// under SSL\n"
        "  -testnet          Use the test network\n";
}

int main(int argc, char* argv[])
{
    setbuf(stdin, NULL);
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    noui_connect();
    ParseParameters(argc, argv);

    if (mapArgs.count("-?") || mapArgs.count("-h") || mapArgs.count("-help"))
    {
        fprintf(stdout, "%s", HelpMessage().c_str());
        return 0;
    }

    ReadConfigFile(mapArgs, mapMultiArgs);

    try
    {
        return CommandLineRPC(argc, argv);
    }
    catch (std::exception& e)
    {
        PrintException(&e, "main()");
    }
    catch (...)
    {
        PrintException(NULL, "main()");
    }
    return 1;
}
