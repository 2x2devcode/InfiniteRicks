#include "watermarkwidget.h"
#include "guiutil.h"

#include <QStackedWidget>
#include <QLabel>
#include <QVBoxLayout>
#include <QResizeEvent>

WatermarkWidget::WatermarkWidget(QWidget *parent) :
    QWidget(parent),
    watermarkLabel(new QLabel(this)),
    stack(new QStackedWidget(this))
{
    setObjectName("contentArea");

    watermarkLabel->setAttribute(Qt::WA_TransparentForMouseEvents);
    watermarkLabel->setAlignment(Qt::AlignCenter);
    watermarkLabel->setPixmap(GUIUtil::fadedPixmap(QPixmap(":/images/splash"), 0.10));

    QVBoxLayout *layout = new QVBoxLayout(this);
    layout->setContentsMargins(12, 12, 12, 12);
    layout->addWidget(stack);

    stack->setAutoFillBackground(false);
    setAutoFillBackground(true);
}

QStackedWidget *WatermarkWidget::stackedWidget() const
{
    return stack;
}

void WatermarkWidget::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);

    const int wmSize = qMin(width(), height()) * 0.55;
    QPixmap base = GUIUtil::fadedPixmap(QPixmap(":/images/splash"), 0.10);
    QPixmap scaled = base.scaled(wmSize, wmSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    watermarkLabel->setPixmap(scaled);
    watermarkLabel->setGeometry((width() - scaled.width()) / 2,
                                (height() - scaled.height()) / 2,
                                scaled.width(),
                                scaled.height());
    watermarkLabel->lower();
    stack->raise();
}
