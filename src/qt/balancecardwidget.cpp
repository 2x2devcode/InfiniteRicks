#include "balancecardwidget.h"
#include <QPainter>
#include <QPen>
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
    gradient.setColorAt(0.0, QColor(0x0a, 0x2a, 0x1a));
    gradient.setColorAt(1.0, QColor(0x00, 0x18, 0x2A));

    painter.setBrush(gradient);
    painter.setPen(Qt::NoPen);
    painter.drawRoundedRect(rect(), 22, 22);

    painter.setPen(QPen(QColor(0x1A, 0x3A, 0x52), 1));
    painter.setBrush(Qt::NoBrush);
    painter.drawRoundedRect(rect().adjusted(0, 0, -1, -1), 22, 22);

    QFrame::paintEvent(event);
}
