#ifndef INTRODIALOG_H
#define INTRODIALOG_H

#include <QDialog>

namespace Ui {
    class IntroDialog;
}

/** First-run dialog to choose where wallet data is stored. */
class IntroDialog : public QDialog
{
    Q_OBJECT

public:
    explicit IntroDialog(QWidget *parent = 0);
    ~IntroDialog();

    QString getDataDirectory() const;

    /** Show intro when needed; returns false if the user cancelled startup. */
    static bool pickDataDirectory();

private slots:
    void on_dataDirectory_textEdited(const QString &arg1);
    void on_browseButton_clicked();
    void on_okButton_clicked();

private:
    Ui::IntroDialog *ui;
    QString dataDir;
    bool fOverriddenDir;

    void setDataDirectory(const QString &dir);
    bool verifyAndSetDataDirectory(const QString &dir);
};

#endif // INTRODIALOG_H
