#ifndef OVERVIEWPAGE_H
#define OVERVIEWPAGE_H

#include <QWidget>

QT_BEGIN_NAMESPACE
class QModelIndex;
class QLabel;
class QWidget;
class QToolButton;
QT_END_NAMESPACE

namespace Ui {
    class OverviewPage;
}
class WalletModel;
class TxViewDelegate;
class TransactionFilterProxy;

/** Overview ("home") page widget */
class OverviewPage : public QWidget
{
    Q_OBJECT

public:
    explicit OverviewPage(QWidget *parent = 0);
    ~OverviewPage();

    void setModel(WalletModel *model);
    void showOutOfSyncWarning(bool fShow);
    void updateSyncStatus(int count, int total, bool showProgress, const QString &statusText);

signals:
    void quickSendClicked();
    void quickReceiveClicked();
    void quickHistoryClicked();
    void quickSettingsClicked();

public slots:
    void setBalance(__int128 balance, __int128 stake, __int128 unconfirmedBalance, __int128 immatureBalance);

signals:
    void transactionClicked(const QModelIndex &index);

private:
    Ui::OverviewPage *ui;
    WalletModel *model;
    qint64 currentBalance;
    qint64 currentStake;
    qint64 currentUnconfirmedBalance;
    qint64 currentImmatureBalance;

    TxViewDelegate *txdelegate;
    TransactionFilterProxy *filter;

    QLabel *labelHeroBalance;
    QLabel *labelBalanceChange;
    QLabel *labelUnitBadge;

    void setupAndroidLayout();

private slots:
    void updateDisplayUnit();
    void handleTransactionClicked(const QModelIndex &index);
};

#endif // OVERVIEWPAGE_H
