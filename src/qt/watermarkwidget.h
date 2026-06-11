#ifndef WATERMARKWIDGET_H
#define WATERMARKWIDGET_H

#include <QWidget>

class QStackedWidget;
class QLabel;

/** Content area with a faded splash watermark behind the active page. */
class WatermarkWidget : public QWidget
{
    Q_OBJECT

public:
    explicit WatermarkWidget(QWidget *parent = 0);

    QStackedWidget *stackedWidget() const;

protected:
    void resizeEvent(QResizeEvent *event);

private:
    QLabel *watermarkLabel;
    QStackedWidget *stack;
};

#endif // WATERMARKWIDGET_H
