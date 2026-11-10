#include "androidbottomnav.h"

#include <QAbstractButton>
#include <QHBoxLayout>
#include <QToolButton>
#include <QButtonGroup>
#include <QIcon>

AndroidBottomNav::AndroidBottomNav(QWidget *parent) :
    QWidget(parent),
    buttonGroup(new QButtonGroup(this)),
    homeButton(new QToolButton(this)),
    sendButton(new QToolButton(this)),
    receiveButton(new QToolButton(this)),
    historyButton(new QToolButton(this)),
    settingsButton(new QToolButton(this))
{
    setObjectName("androidBottomNav");

    QHBoxLayout *layout = new QHBoxLayout(this);
    layout->setContentsMargins(6, 4, 6, 8);
    layout->setSpacing(2);

    QList<QToolButton*> buttons;
    buttons << homeButton << sendButton << receiveButton << historyButton;
    const char *labels[] = { QT_TR_NOOP("Home"), QT_TR_NOOP("Send"), QT_TR_NOOP("Receive"), QT_TR_NOOP("History") };
    const char *icons[] = { ":/icons/overview", ":/icons/send", ":/icons/receiving_addresses", ":/icons/history" };

    for (int i = 0; i < buttons.size(); ++i) {
        QToolButton *button = buttons[i];
        button->setObjectName("androidNavButton");
        button->setToolButtonStyle(Qt::ToolButtonTextUnderIcon);
        button->setIconSize(QSize(26, 26));
        button->setIcon(QIcon(icons[i]));
        button->setText(tr(labels[i]));
        button->setCheckable(true);
        button->setAutoRaise(false);
        button->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Preferred);
        buttonGroup->addButton(button, i);
        layout->addWidget(button, 1);
    }

    settingsButton->setObjectName("androidNavSettingsButton");
    settingsButton->setToolButtonStyle(Qt::ToolButtonTextUnderIcon);
    settingsButton->setIconSize(QSize(26, 26));
    settingsButton->setIcon(QIcon(":/icons/options"));
    settingsButton->setText(tr("Settings"));
    settingsButton->setCheckable(false);
    settingsButton->setAutoRaise(false);
    settingsButton->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Preferred);
    layout->addWidget(settingsButton, 1);

    homeButton->setChecked(true);

    connect(homeButton, SIGNAL(clicked()), this, SIGNAL(homeClicked()));
    connect(sendButton, SIGNAL(clicked()), this, SIGNAL(sendClicked()));
    connect(receiveButton, SIGNAL(clicked()), this, SIGNAL(receiveClicked()));
    connect(historyButton, SIGNAL(clicked()), this, SIGNAL(historyClicked()));
    connect(settingsButton, SIGNAL(clicked()), this, SIGNAL(settingsClicked()));
}

void AndroidBottomNav::setCurrentIndex(int index)
{
    if (QAbstractButton *button = buttonGroup->button(index))
        button->setChecked(true);
}
