#ifndef RPCCONSOLE_H
#define RPCCONSOLE_H

#include <QDialog>
#include <QStringList>

QT_BEGIN_NAMESPACE
class QHideEvent;
class QItemSelection;
class QMenu;
class QPoint;
class QShowEvent;
QT_END_NAMESPACE

namespace Ui {
    class RPCConsole;
}
class ClientModel;
class PeerTableModel;
class BanTableModel;
class CNodeStats;

/** Local Bitcoin RPC console. */
class RPCConsole: public QDialog
{
    Q_OBJECT

public:
    explicit RPCConsole(QWidget *parent = 0);
    ~RPCConsole();

    void setClientModel(ClientModel *model);

    enum MessageClass {
        MC_ERROR,
        MC_DEBUG,
        CMD_REQUEST,
        CMD_REPLY,
        CMD_ERROR
    };

protected:
    virtual bool eventFilter(QObject* obj, QEvent *event);
    virtual void showEvent(QShowEvent *event);
    virtual void hideEvent(QHideEvent *event);

private slots:
    void on_lineEdit_returnPressed();
    void on_tabWidget_currentChanged(int index);
    /** open the debug.log from the current datadir */
    void on_openDebugLogfileButton_clicked();
    /** display messagebox with program parameters (same as bitcoin-qt --help) */
    void on_showCLOptionsButton_clicked();
    void on_closeButton_clicked();

    void showPeersTableContextMenu(const QPoint& point);
    void showBanTableContextMenu(const QPoint& point);
    void showOrHideBanTableIfRequired();
    void clearSelectedNode();

    void walletSalvage();
    void walletRescan();
    void walletZaptxes1();
    void walletZaptxes2();
    void walletUpgrade();
    void walletReindex();
    void walletResync();

    void peerSelected(const QItemSelection& selected, const QItemSelection& deselected);
    void peerLayoutChanged();
    void disconnectSelectedNode();
    void banSelectedNode(int bantime);
    void banNode1h();
    void banNode24h();
    void banNode7d();
    void banNode365d();
    void unbanSelectedNode();

public slots:
    void clear();
    void message(int category, const QString &message, bool html = false);
    /** Set number of connections shown in the UI */
    void setNumConnections(int count);
    /** Set number of blocks shown in the UI */
    void setNumBlocks(int count, int countOfPeers);
    /** Go forward or back in history */
    void browseHistory(int offset);
    /** Scroll console view to end */
    void scrollToEnd();
signals:
    // For RPC command executor
    void stopExecutor();
    void cmdRequest(const QString &command);
    void handleRestart(QStringList args);

private:
    void startExecutor();
    void buildParameterlist(QString arg);
    void updateNodeDetail(const CNodeStats *stats);

    enum ColumnWidths {
        ADDRESS_COLUMN_WIDTH = 170,
        SUBVERSION_COLUMN_WIDTH = 140,
        PING_COLUMN_WIDTH = 80,
        BANSUBNET_COLUMN_WIDTH = 200,
        BANTIME_COLUMN_WIDTH = 250
    };

    Ui::RPCConsole *ui;
    ClientModel *clientModel;
    PeerTableModel *peerModel;
    BanTableModel *banModel;
    QStringList history;
    int historyPtr;
    int cachedNodeid;
    QMenu *peersTableContextMenu;
    QMenu *banTableContextMenu;
};

#endif // RPCCONSOLE_H
