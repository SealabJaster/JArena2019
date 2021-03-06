﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Shapes;
using Editor_CSharp.Serial;
using Editor_CSharp.Util;

namespace Editor_CSharp.Controls
{
    /// <summary>
    /// Interaction logic for VectorEditor.xaml
    /// </summary>
    public partial class VectorEditor : UserControl, IEditorControl
    {
        public FieldDef Def { private set; get; }
        public List<LabeledNumberBox> Inputs { private set; get; }

        public VectorEditor(ViewEditor editor, ArchiveObject obj, FieldDef def)
        {
            InitializeComponent();
            this.Def = def;
            this.Inputs = new List<LabeledNumberBox>();
            this.label.Content = def.name;

            if (def.inputStaticLength >= 1)
            {
                var box = new LabeledNumberBox("X:", def.inputSubtype);
                this.Inputs.Add(box);
                this.panel.Children.Add(box);

                if(obj != null) box.input.Text = NumberHelper.ConvertValue<Object>(obj.Values[0]).ToString();
            }
            if (def.inputStaticLength >= 2)
            {
                var box = new LabeledNumberBox("Y:", def.inputSubtype);
                this.Inputs.Add(box);
                this.panel.Children.Add(box);

                if (obj != null) box.input.Text = NumberHelper.ConvertValue<Object>(obj.Values[1]).ToString();
            }
            if (def.inputStaticLength >= 3)
            {
                var box = new LabeledNumberBox("Z:", def.inputSubtype);
                this.Inputs.Add(box);
                this.panel.Children.Add(box);

                if (obj != null) box.input.Text = NumberHelper.ConvertValue<Object>(obj.Values[2]).ToString();
            }
            this.nullbox.Checked   += (_, __) => this.Inputs.ForEach(i => i.IsEnabled = true);
            this.nullbox.Unchecked += (_, __) => this.Inputs.ForEach(i => i.IsEnabled = false);
            this.nullbox.Checked   += (_, __) => editor.UpdateGameClient();
            this.nullbox.Unchecked += (_, __) => editor.UpdateGameClient();
            this.nullbox.Visibility = (def.isNullable) ? Visibility.Visible : Visibility.Hidden;
            this.nullbox.IsChecked  = (def.isNullable) ? obj != null : true;

            foreach(var input in this.Inputs)
            {
                input.input.TextChanged += (s, __) =>
                {
                    try
                    {
                        editor.UpdateGameClient();
                    }
                    catch(FormatException ex)
                    {
                        input.SetError(ex.Message);
                    }
                };
            }
        }

        public ArchiveObject GetObject()
        {
            if (!this.nullbox.IsChecked)
                return null;

            var obj = new ArchiveObject();
            obj.Name = this.Def.name;

            this.Inputs.ForEach(b => obj.AddValue(NumberHelper.MakeValue(b.input.Text, this.Def.inputSubtype)));

            return obj;
        }
    }
}
