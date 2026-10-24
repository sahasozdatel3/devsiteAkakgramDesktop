/*
This file is part of Telegram Desktop,
the official desktop application for the Telegram messaging service.

For license and copyright information please follow this link:
https://github.com/telegramdesktop/tdesktop/blob/master/LEGAL
*/
#pragma once

#include "ui/rp_widget.h"

namespace Window {

class PanelsFrame final : public Ui::RpWidget {
public:
	explicit PanelsFrame(not_null<QWidget*> parent);

	void setPanels(std::vector<QRect> panels);

private:
	void paintEvent(QPaintEvent *e) override;

	std::vector<QRect> _panels;

};

} // namespace Window
