#pragma once

#include <imoinfo.h>

#include <QCoreApplication>
#include <QFile>
#include <QLocale>
#include <QSettings>
#include <QString>
#include <QStringList>
#include <QTranslator>

namespace PluginTranslations {

inline QString resolveConfiguredLanguage(MOBase::IOrganizer* organizer)
{
  QStringList candidateIniPaths;
  if (organizer != nullptr && !organizer->basePath().isEmpty()) {
    candidateIniPaths << (organizer->basePath() + "/ModOrganizer.ini");
  }
  if (QCoreApplication::instance() != nullptr) {
    candidateIniPaths << (QCoreApplication::applicationDirPath() + "/ModOrganizer.ini");
  }

  for (const auto& iniPath : candidateIniPaths) {
    if (!QFile::exists(iniPath)) {
      continue;
    }
    const QSettings settings(iniPath, QSettings::IniFormat);
    const QString configured = settings.value("Settings/language").toString().trimmed();
    if (!configured.isEmpty()) {
      return configured;
    }
  }

  const QStringList uiLanguages = QLocale::system().uiLanguages();
  if (!uiLanguages.isEmpty() && !uiLanguages.front().trimmed().isEmpty()) {
    return uiLanguages.front().trimmed();
  }
  return QLocale::system().name();
}

inline void installPluginTranslator(
    MOBase::IOrganizer* organizer, const QString& pluginBaseName, const char* probeContext, const char* probeSource)
{
  auto* app = QCoreApplication::instance();
  if (app == nullptr) {
    return;
  }

  QString langCode = resolveConfiguredLanguage(organizer);
  langCode.replace('-', '_');
  if (langCode.isEmpty() || langCode.compare("en", Qt::CaseInsensitive) == 0
      || langCode.startsWith("en_", Qt::CaseInsensitive)) {
    return;
  }

  const QString translationsDir = QCoreApplication::applicationDirPath() + "/translations";
  auto* bootstrapTranslator     = new QTranslator(app);
  const QString primaryLang     = langCode.section('_', 0, 0);

  if (!bootstrapTranslator->load(pluginBaseName + "_" + langCode, translationsDir)
      && !bootstrapTranslator->load(pluginBaseName + "_" + primaryLang, translationsDir)) {
    delete bootstrapTranslator;
    return;
  }

  QCoreApplication::installTranslator(bootstrapTranslator);

  if (organizer != nullptr && probeContext != nullptr && probeSource != nullptr) {
    organizer->onUserInterfaceInitialized([bootstrapTranslator, probeContext, probeSource](QMainWindow*) {
      QCoreApplication::removeTranslator(bootstrapTranslator);
      const QString probed = QCoreApplication::translate(probeContext, probeSource);
      if (probed != QString::fromUtf8(probeSource)) {
        // MO2 MainWindow installed its own managed QTranslator for this plugin; avoid duplicate retention.
        bootstrapTranslator->deleteLater();
      } else {
        // Fallback when MO2's initial locale string (e.g. hyphenated 'ko-KR') missed the '<plugin>_ko.qm' file.
        QCoreApplication::installTranslator(bootstrapTranslator);
      }
    });
  }
}

} // namespace PluginTranslations
