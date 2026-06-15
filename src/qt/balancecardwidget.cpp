#include "balancecardwidget.h"
#include "guiconstants.h"

#include <QPainter>
#include <QLinearGradient>
#include <QPaintEvent>

BalanceCardWidget::BalanceCardWidget(QWidget *parent) :
    QFrame(parent)
{
    setObjectName("balanceHeroCard");
    setFrameShape(QFrame::NoFrame);
}

void BalanceCardWidget::paintEvent(QPaintEvent *event)
{
    Q_UNUSED(event);

    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing, true);

    QLinearGradient gradient(0, 0, width(), height());
    gradient.setColorAt(0.0, COLOR_BRAND_DARK);
    gradient.setColorAt(0.55, COLOR_BRAND);
    gradient.setColorAt(1.0, QColor(107, 196, 90));

    painter.setBrush(gradient);
    painter.setPen(Qt::NoPen);
    painter.drawRoundedRect(rect(), 22, 22);

    QFrame::paintEvent(event);
}
