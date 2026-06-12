#ifndef ANDROIDBOTTOMNAV_H
#define ANDROIDBOTTOMNAV_H

#include <QWidget>

class QToolButton;
class QButtonGroup;

class AndroidBottomNav : public QWidget
{
    Q_OBJECT

public:
    explicit AndroidBottomNav(QWidget *parent = 0);

    void setCurrentIndex(int index);

signals:
    void homeClicked();
    void sendClicked();
    void receiveClicked();
    void historyClicked();

private:
    QButtonGroup *buttonGroup;
    QToolButton *homeButton;
    QToolButton *sendButton;
    QToolButton *receiveButton;
    QToolButton *historyButton;
};

#endif // ANDROIDBOTTOMNAV_H
