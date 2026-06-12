#include "overviewpage.h"
#include "ui_overviewpage.h"

#include "walletmodel.h"
#include "bitcoinunits.h"
#include "optionsmodel.h"
#include "transactiontablemodel.h"
#include "transactionfilterproxy.h"
#include "guiutil.h"
#include "guiconstants.h"

#include <QAbstractItemDelegate>
#include <QPainter>
#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QLabel>
#include <QToolButton>
#include <QPushButton>
#include <QFrame>
#include <QPixmap>
#include <QIcon>

#define DECORATION_SIZE OVERVIEW_TX_ICON_SIZE
#define NUM_ITEMS 5

class TxViewDelegate : public QAbstractItemDelegate
{
    Q_OBJECT
public:
    TxViewDelegate(): QAbstractItemDelegate(), unit(BitcoinUnits::BTC)
    {

    }

    inline void paint(QPainter *painter, const QStyleOptionViewItem &option,
                      const QModelIndex &index ) const
    {
        painter->save();

        QIcon icon = qvariant_cast<QIcon>(index.data(Qt::DecorationRole));
        QRect mainRect = option.rect;
        QRect decorationRect(mainRect.topLeft(), QSize(DECORATION_SIZE, DECORATION_SIZE));
        int xspace = DECORATION_SIZE + 8;
        int ypad = 6;
        int halfheight = (mainRect.height() - 2*ypad)/2;
        QRect amountRect(mainRect.left() + xspace, mainRect.top()+ypad, mainRect.width() - xspace, halfheight);
        QRect addressRect(mainRect.left() + xspace, mainRect.top()+ypad+halfheight, mainRect.width() - xspace, halfheight);
        icon.paint(painter, decorationRect);

        QDateTime date = index.data(TransactionTableModel::DateRole).toDateTime();
        QString address = index.data(Qt::DisplayRole).toString();
        __int128 amount = index.data(TransactionTableModel::AmountRole).toLongLong();
        bool confirmed = index.data(TransactionTableModel::ConfirmedRole).toBool();
        QVariant value = index.data(Qt::ForegroundRole);
        QColor foreground = option.palette.color(QPalette::Text);
        if(qVariantCanConvert<QColor>(value))
        {
            foreground = qvariant_cast<QColor>(value);
        }

        painter->setPen(foreground);
        painter->drawText(addressRect, Qt::AlignLeft|Qt::AlignVCenter, address);

        if(amount < 0)
        {
            foreground = COLOR_NEGATIVE;
        }
        else if(!confirmed)
        {
            foreground = COLOR_UNCONFIRMED;
        }
        else
        {
            foreground = option.palette.color(QPalette::Text);
        }
        painter->setPen(foreground);
        QString amountText = BitcoinUnits::formatWithUnit(unit, amount, true);
        if(!confirmed)
        {
            amountText = QString("[") + amountText + QString("]");
        }
        painter->drawText(amountRect, Qt::AlignRight|Qt::AlignVCenter, amountText);

        painter->setPen(option.palette.color(QPalette::Text));
        painter->drawText(amountRect, Qt::AlignLeft|Qt::AlignVCenter, GUIUtil::dateTimeStr(date));

        painter->restore();
    }

    inline QSize sizeHint(const QStyleOptionViewItem &option, const QModelIndex &index) const
    {
#if defined(Q_OS_ANDROID)
        Q_UNUSED(index);
        return QSize(option.rect.width() > 0 ? option.rect.width() : 320, 56);
#else
        return QSize(DECORATION_SIZE, DECORATION_SIZE);
#endif
    }

    int unit;

};
#include "overviewpage.moc"

OverviewPage::OverviewPage(QWidget *parent) :
    QWidget(parent),
    ui(new Ui::OverviewPage),
    currentBalance(-1),
    currentStake(0),
    currentUnconfirmedBalance(-1),
    currentImmatureBalance(-1),
    txdelegate(new TxViewDelegate()),
    filter(0),
    labelHeroBalance(0),
    labelBalanceChange(0),
    labelUnitBadge(0)
{
    ui->setupUi(this);

    // Recent transactions
    ui->listTransactions->setItemDelegate(txdelegate);
    ui->listTransactions->setIconSize(QSize(DECORATION_SIZE, DECORATION_SIZE));
    ui->listTransactions->setMinimumHeight(NUM_ITEMS * (DECORATION_SIZE + 14));
    ui->listTransactions->setAttribute(Qt::WA_MacShowFocusRect, false);

    connect(ui->listTransactions, SIGNAL(clicked(QModelIndex)), this, SLOT(handleTransactionClicked(QModelIndex)));

    // init "out of sync" warning labels
    ui->labelWalletStatus->setText("(" + tr("out of sync") + ")");
    ui->labelTransactionsStatus->setText("(" + tr("out of sync") + ")");

    // start with displaying the "out of sync" warnings
    showOutOfSyncWarning(true);
    ui->frameSync->setVisible(false);

#if defined(Q_OS_ANDROID)
    setupAndroidLayout();
#endif
}

void OverviewPage::handleTransactionClicked(const QModelIndex &index)
{
    if(filter)
        emit transactionClicked(filter->mapToSource(index));
}

OverviewPage::~OverviewPage()
{
    delete ui;
}

void OverviewPage::setBalance(__int128 balance, __int128 stake, __int128 unconfirmedBalance, __int128 immatureBalance)
{
    int unit = model ? model->getOptionsModel()->getDisplayUnit() : BitcoinUnits::BTC;
    currentBalance = balance;
    currentStake = stake;
    currentUnconfirmedBalance = unconfirmedBalance;
    currentImmatureBalance = immatureBalance;
    ui->labelBalance->setText(BitcoinUnits::formatWithUnit(unit, balance));
    ui->labelStake->setText(BitcoinUnits::formatWithUnit(unit, stake));
    ui->labelUnconfirmed->setText(BitcoinUnits::formatWithUnit(unit, unconfirmedBalance));
    ui->labelImmature->setText(BitcoinUnits::formatWithUnit(unit, immatureBalance));
    __int128 totalBalance = balance;
    totalBalance += stake;
    totalBalance += unconfirmedBalance;
    totalBalance += immatureBalance;
    const QString totalText = BitcoinUnits::formatWithUnit(unit, totalBalance);
    ui->labelTotal->setText(totalText);

    if (labelHeroBalance)
        labelHeroBalance->setText(totalText);
    if (labelUnitBadge)
        labelUnitBadge->setText(BitcoinUnits::name(unit));
    if (labelBalanceChange) {
        QString changeText;
        if (stake > 0)
            changeText = tr("Staking %1").arg(BitcoinUnits::formatWithUnit(unit, stake));
        else if (unconfirmedBalance > 0)
            changeText = tr("Pending %1").arg(BitcoinUnits::formatWithUnit(unit, unconfirmedBalance));
        else
            changeText = tr("Spendable %1").arg(BitcoinUnits::formatWithUnit(unit, balance));
        labelBalanceChange->setText(changeText);
    }

    // only show immature (newly mined) balance if it's non-zero, so as not to complicate things
    // for the non-mining users
    bool showImmature = immatureBalance != 0;
    ui->labelImmature->setVisible(showImmature);
    ui->labelImmatureText->setVisible(showImmature);
}

void OverviewPage::setModel(WalletModel *model)
{
    this->model = model;
    if(model && model->getOptionsModel())
    {
        // Set up transaction list
        filter = new TransactionFilterProxy();
        filter->setSourceModel(model->getTransactionTableModel());
        filter->setLimit(NUM_ITEMS);
        filter->setDynamicSortFilter(true);
        filter->setSortRole(Qt::EditRole);
        filter->setShowInactive(false);
        filter->sort(TransactionTableModel::Status, Qt::DescendingOrder);

        ui->listTransactions->setModel(filter);
        ui->listTransactions->setModelColumn(TransactionTableModel::ToAddress);

        // Keep up to date with wallet
        setBalance(model->getBalance(), model->getStake(), model->getUnconfirmedBalance(), model->getImmatureBalance());
        connect(model, SIGNAL(balanceChanged(__int128, __int128, __int128, __int128)), this, SLOT(setBalance(__int128, __int128, __int128, __int128)));

        connect(model->getOptionsModel(), SIGNAL(displayUnitChanged(int)), this, SLOT(updateDisplayUnit()));
    }

    // update the display unit, to not use the default ("BTC")
    updateDisplayUnit();
}

void OverviewPage::updateDisplayUnit()
{
    if(model && model->getOptionsModel())
    {
        if(currentBalance != -1)
            setBalance(currentBalance, model->getStake(), currentUnconfirmedBalance, currentImmatureBalance);

        // Update txdelegate->unit with the current unit
        txdelegate->unit = model->getOptionsModel()->getDisplayUnit();

        ui->listTransactions->update();
    }
}

void OverviewPage::showOutOfSyncWarning(bool fShow)
{
#if defined(Q_OS_ANDROID)
    Q_UNUSED(fShow);
#else
    ui->labelWalletStatus->setVisible(fShow);
    ui->labelTransactionsStatus->setVisible(fShow);
#endif
}

void OverviewPage::updateSyncStatus(int count, int total, bool showProgress, const QString &statusText)
{
    ui->frameSync->setVisible(showProgress);
    if (!showProgress)
        return;

    ui->labelSyncStatus->setText(statusText);
    ui->progressBarSync->setMaximum(total > 0 ? total : 1);
    ui->progressBarSync->setValue(count);
    if (total > count) {
        ui->progressBarSync->setFormat(tr("~%n block(s) remaining", "", total - count));
    } else {
        ui->progressBarSync->setFormat(QString());
    }
}

#if defined(Q_OS_ANDROID)
void OverviewPage::setupAndroidLayout()
{
    ui->verticalLayoutMain->setContentsMargins(16, 12, 16, 8);
    ui->verticalLayoutMain->setSpacing(14);

    QWidget *header = new QWidget(this);
    header->setObjectName("androidHeader");
    QHBoxLayout *headerLayout = new QHBoxLayout(header);
    headerLayout->setContentsMargins(0, 0, 0, 0);
    headerLayout->setSpacing(12);

    QLabel *logo = new QLabel(header);
    logo->setObjectName("androidHeaderLogo");
    logo->setPixmap(QPixmap(":/icons/bitcoin").scaled(32, 32, Qt::KeepAspectRatio, Qt::SmoothTransformation));
    logo->setAlignment(Qt::AlignCenter);

    QLabel *title = new QLabel(tr("InfiniteRicks Wallet"), header);
    title->setObjectName("androidHeaderTitle");

    headerLayout->addWidget(logo);
    headerLayout->addWidget(title, 1);
    ui->verticalLayoutMain->insertWidget(0, header);

    while (QLayoutItem *spacer = ui->verticalLayout_2->takeAt(ui->verticalLayout_2->count() - 1))
        delete spacer;
    while (QLayoutItem *spacer = ui->verticalLayout_3->takeAt(ui->verticalLayout_3->count() - 1))
        delete spacer;

    QLayoutItem *horizontalItem = ui->verticalLayoutMain->takeAt(2);
    delete horizontalItem;

    QVBoxLayout *bodyLayout = new QVBoxLayout();
    bodyLayout->setSpacing(14);
    bodyLayout->setContentsMargins(0, 0, 0, 0);

    ui->frame->setObjectName("balanceHeroCard");
    ui->label_5->setVisible(false);
    ui->labelWalletStatus->setVisible(false);
    ui->line->setVisible(false);
    ui->labelTotalText->setVisible(false);
    ui->labelTotal->setVisible(false);
    ui->label->setVisible(false);
    ui->labelBalance->setVisible(false);
    ui->label_6->setVisible(false);
    ui->labelStake->setVisible(false);
    ui->label_3->setVisible(false);
    ui->labelUnconfirmed->setVisible(false);
    ui->labelImmatureText->setVisible(false);
    ui->labelImmature->setVisible(false);

    QVBoxLayout *heroLayout = ui->verticalLayout_4;
  heroLayout->insertLayout(0, new QHBoxLayout());
    QHBoxLayout *heroTop = qobject_cast<QHBoxLayout*>(heroLayout->itemAt(0)->layout());
    QLabel *caption = new QLabel(tr("Current balance"), ui->frame);
    caption->setObjectName("labelBalanceCaption");
    labelUnitBadge = new QLabel(ui->frame);
    labelUnitBadge->setObjectName("labelUnitBadge");
    labelUnitBadge->setText("RICK");
    heroTop->addWidget(caption);
    heroTop->addWidget(labelUnitBadge);
    heroTop->addStretch();
    QPushButton *settingsButton = new QPushButton(ui->frame);
    settingsButton->setObjectName("heroSettingsButton");
    settingsButton->setIcon(QIcon(":/icons/options"));
    settingsButton->setToolTip(tr("Settings"));
    connect(settingsButton, SIGNAL(clicked()), this, SIGNAL(quickSettingsClicked()));
    heroTop->addWidget(settingsButton);

    labelHeroBalance = new QLabel(ui->frame);
    labelHeroBalance->setObjectName("labelHeroBalance");
    labelHeroBalance->setText(ui->labelTotal->text());
    heroLayout->insertWidget(1, labelHeroBalance);

    labelBalanceChange = new QLabel(ui->frame);
    labelBalanceChange->setObjectName("labelBalanceChange");
    labelBalanceChange->setText(tr("Spendable 0 RICK"));
    heroLayout->insertWidget(2, labelBalanceChange);

    while (heroLayout->count() > 3) {
        QLayoutItem *item = heroLayout->takeAt(3);
        delete item;
    }

    QWidget *quickActions = new QWidget(this);
    quickActions->setObjectName("quickActionsRow");
    QHBoxLayout *quickLayout = new QHBoxLayout(quickActions);
    quickLayout->setContentsMargins(0, 0, 0, 0);
    quickLayout->setSpacing(10);

    struct QuickAction {
        const char *icon;
        const char *label;
    };
    const QuickAction actions[] = {
        { ":/icons/send", QT_TR_NOOP("Send") },
        { ":/icons/receiving_addresses", QT_TR_NOOP("Receive") },
        { ":/icons/history", QT_TR_NOOP("History") },
        { ":/icons/options", QT_TR_NOOP("More") }
    };

    for (unsigned int i = 0; i < sizeof(actions) / sizeof(actions[0]); ++i) {
        QToolButton *button = new QToolButton(quickActions);
        button->setObjectName("quickActionButton");
        button->setToolButtonStyle(Qt::ToolButtonTextUnderIcon);
        button->setIconSize(QSize(22, 22));
        button->setIcon(QIcon(actions[i].icon));
        button->setText(tr(actions[i].label));
        if (i == 0)
            connect(button, SIGNAL(clicked()), this, SIGNAL(quickSendClicked()));
        else if (i == 1)
            connect(button, SIGNAL(clicked()), this, SIGNAL(quickReceiveClicked()));
        else if (i == 2)
            connect(button, SIGNAL(clicked()), this, SIGNAL(quickHistoryClicked()));
        else
            connect(button, SIGNAL(clicked()), this, SIGNAL(quickSettingsClicked()));
        quickLayout->addWidget(button, 1);
    }

    ui->frame_2->setObjectName("assetsCard");
    ui->label_4->setObjectName("assetsSectionTitle");
    ui->label_4->setText(tr("Recent activity"));
    ui->labelTransactionsStatus->setObjectName("assetsFilterLabel");
    ui->labelTransactionsStatus->setText(tr("Latest"));
    ui->labelTransactionsStatus->setAlignment(Qt::AlignRight | Qt::AlignVCenter);

    ui->listTransactions->setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    ui->listTransactions->setMinimumHeight(NUM_ITEMS * 58);

    bodyLayout->addWidget(ui->frame);
    bodyLayout->addWidget(quickActions);
    bodyLayout->addWidget(ui->frame_2, 1);
    ui->verticalLayoutMain->addLayout(bodyLayout, 1);
}
#endif
