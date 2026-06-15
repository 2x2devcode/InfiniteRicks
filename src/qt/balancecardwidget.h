#ifndef BALANCECARDWIDGET_H
#define BALANCECARDWIDGET_H

#include <QFrame>

class BalanceCardWidget : public QFrame
{
    Q_OBJECT

public:
    explicit BalanceCardWidget(QWidget *parent = 0);

protected:
    void paintEvent(QPaintEvent *event);
};

#endif // BALANCECARDWIDGET_H
