/*
This file is part of Telegram Desktop,
the official desktop application for the Telegram messaging service.

For license and copyright information please follow this link:
https://github.com/telegramdesktop/tdesktop/blob/master/LEGAL
*/
#include "window/window_panels_frame.h"

#include "ui/painter.h"
#include "styles/style_basic.h"
#include "styles/style_widgets.h"
#include "styles/style_window.h"

#include <QtGui/QPainterPath>

namespace Window {
namespace {

[[nodiscard]] QColor BackdropColor() {
	const auto base = st::windowBg->c;
	const auto light = (base.lightness() > 128);
	const auto keep = light ? 0.88 : 0.55;
	return QColor::fromRgbF(
		base.redF() * keep,
		base.greenF() * keep,
		base.blueF() * keep);
}

[[nodiscard]] QColor BorderColor() {
	auto result = st::windowSubTextFg->c;
	result.setAlpha(46);
	return result;
}

} // namespace

PanelsFrame::PanelsFrame(not_null<QWidget*> parent)
: RpWidget(parent) {
	setAttribute(Qt::WA_TransparentForMouseEvents);
	setAttribute(Qt::WA_NoSystemBackground);
}

void PanelsFrame::setPanels(std::vector<QRect> panels) {
	if (_panels == panels) {
		return;
	}
	_panels = std::move(panels);
	update();
}

void PanelsFrame::paintEvent(QPaintEvent *e) {
	if (_panels.empty()) {
		return;
	}
	auto p = QPainter(this);
	auto hq = PainterHighQualityEnabler(p);

	const auto radius = qreal(st::akakPanelRadius);
	const auto half = st::lineWidth / 2.;

	auto cards = QPainterPath();
	for (const auto &panel : _panels) {
		cards.addRoundedRect(QRectF(panel), radius, radius);
	}
	auto backdrop = QPainterPath();
	backdrop.addRect(QRectF(rect()));
	p.fillPath(backdrop.subtracted(cards), BackdropColor());

	p.setBrush(Qt::NoBrush);
	p.setPen(QPen(BorderColor(), st::lineWidth));
	for (const auto &panel : _panels) {
		p.drawRoundedRect(
			QRectF(panel).adjusted(half, half, -half, -half),
			radius,
			radius);
	}
}

} // namespace Window
