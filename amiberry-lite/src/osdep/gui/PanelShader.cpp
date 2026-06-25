#include <cstring>
#include <guisan.hpp>
#include <guisan/sdl.hpp>
#include "SelectorEntry.hpp"
#include "StringListModel.h"

#include "sysdeps.h"
#include "options.h"
#include "gui_handling.h"

extern void destroy_crtemu();

static const std::vector<std::string> shader_names = {
    "1084S (Commodore 1084S CRT)",
    "TV (Generic TV phosphor)",
    "PC (Computer monitor)",
    "Lite (Minimal scanlines)",
};
static const char* const shader_values[] = { "1084", "tv", "pc", "lite" };
static const int NUM_SHADER_PRESETS = 4;

static gcn::CheckBox* chkShaderEnabled;
static gcn::Label*    lblShaderPreset;
static gcn::DropDown* cboShaderPreset;
static gcn::StringListModel shaderListModel(shader_names);

static int shader_to_index(const char* name)
{
    if (!name || !name[0] || std::strcmp(name, "none") == 0)
        return 0;
    for (int i = 0; i < NUM_SHADER_PRESETS; ++i)
        if (strcasecmp(name, shader_values[i]) == 0)
            return i;
    return 0;
}

class ShaderActionListener : public gcn::ActionListener
{
public:
    void action(const gcn::ActionEvent& actionEvent) override
    {
        if (actionEvent.getSource() == chkShaderEnabled) {
            if (chkShaderEnabled->isSelected()) {
                const int idx = cboShaderPreset->getSelected();
                strncpy(amiberry_options.shader, shader_values[idx],
                        sizeof(amiberry_options.shader) - 1);
                cboShaderPreset->setEnabled(true);
            } else {
                strncpy(amiberry_options.shader, "none",
                        sizeof(amiberry_options.shader) - 1);
                cboShaderPreset->setEnabled(false);
            }
        } else if (actionEvent.getSource() == cboShaderPreset) {
            const int idx = cboShaderPreset->getSelected();
            if (idx >= 0 && idx < NUM_SHADER_PRESETS)
                strncpy(amiberry_options.shader, shader_values[idx],
                        sizeof(amiberry_options.shader) - 1);
        }
        destroy_crtemu(); // recreated on next frame with new setting
    }
};
static ShaderActionListener* shaderActionListener;

void InitPanelShader(const config_category& category)
{
    shaderActionListener = new ShaderActionListener();

    chkShaderEnabled = new gcn::CheckBox("Enable CRT Shader");
    chkShaderEnabled->setId("chkShaderEnabled");
    chkShaderEnabled->addActionListener(shaderActionListener);

    lblShaderPreset = new gcn::Label("Preset:");
    cboShaderPreset = new gcn::DropDown(&shaderListModel);
    cboShaderPreset->setId("cboShaderPreset");
    cboShaderPreset->setWidth(300);
    cboShaderPreset->addActionListener(shaderActionListener);

    int pos_y = DISTANCE_BORDER;

    category.panel->add(chkShaderEnabled, DISTANCE_BORDER, pos_y);
    pos_y += chkShaderEnabled->getHeight() + DISTANCE_NEXT_Y;

    category.panel->add(lblShaderPreset, DISTANCE_BORDER, pos_y);
    category.panel->add(cboShaderPreset, DISTANCE_BORDER + 80, pos_y);

    RefreshPanelShader();
}

void ExitPanelShader()
{
    delete chkShaderEnabled;
    delete lblShaderPreset;
    delete cboShaderPreset;
    delete shaderActionListener;
}

void RefreshPanelShader()
{
    const bool enabled = (std::strcmp(amiberry_options.shader, "none") != 0);
    chkShaderEnabled->setSelected(enabled);
    if (enabled)
        cboShaderPreset->setSelected(shader_to_index(amiberry_options.shader));
    cboShaderPreset->setEnabled(enabled);
}

bool HelpPanelShader(std::vector<std::string>& helptext)
{
    helptext.clear();
    helptext.emplace_back("This panel controls the CRT shader applied to the Amiga display output.");
    helptext.emplace_back(" ");
    helptext.emplace_back("- Enable CRT Shader: Toggles the shader on or off. When off, the Amiga");
    helptext.emplace_back("  screen is rendered as clean pixels with no CRT processing.");
    helptext.emplace_back(" ");
    helptext.emplace_back("- Preset: Selects which CRT style to apply:");
    helptext.emplace_back(" ");
    helptext.emplace_back("  1084S  Emulates the Commodore 1084S monitor with bloom, curved scanlines");
    helptext.emplace_back("         and warm phosphor glow. Recommended for Amiga nostalgia.");
    helptext.emplace_back(" ");
    helptext.emplace_back("  TV     Generic television CRT appearance.");
    helptext.emplace_back(" ");
    helptext.emplace_back("  PC     Computer monitor style — lighter scanlines, less bloom.");
    helptext.emplace_back(" ");
    helptext.emplace_back("  Lite   Minimal scanlines only, no bloom or curvature.");
    helptext.emplace_back(" ");
    helptext.emplace_back("Changes take effect immediately without restarting the emulation.");
    helptext.emplace_back("The setting is saved in ~/.config/amiberry-lite/amiberry.conf.");
    return true;
}
