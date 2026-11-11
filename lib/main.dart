import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'message_logic.dart';

void main() => runApp(const PayamYar());

class PayamYar extends StatefulWidget {
  const PayamYar({super.key});
  @override
  State<PayamYar> createState() => _PayamYarState();
}
class _PayamYarState extends State<PayamYar> {
  int palette = 0;
  ThemeMode mode = ThemeMode.system;
  double scale = 1;
  bool dense = false;
  bool privatePreview = true;
  final colors = [const Color(0xFF087E83), const Color(0xFF284F99), const Color(0xFF7144BC), const Color(0xFF973954), const Color(0xFF357447), const Color(0xFFA67821)];
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      palette = (p.getInt('palette') ?? 0).clamp(0, colors.length-1);
      mode = ThemeMode.values[(p.getInt('theme') ?? 0).clamp(0, 2)];
      scale = p.getDouble('scale') ?? 1;
      dense = p.getBool('dense') ?? false;
      privatePreview = p.getBool('privatePreview') ?? true;
    });
  }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('palette', palette);
    await p.setInt('theme', mode.index);
    await p.setDouble('scale', scale);
    await p.setBool('dense', dense);
    await p.setBool('privatePreview', privatePreview);
  }
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'پیامیار',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: colors[palette]), useMaterial3: true, fontFamily: 'sans-serif'),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: colors[palette], brightness: Brightness.dark), useMaterial3: true),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!)),
      home: HomeScreen(settings: SettingsState(palette, mode, scale, dense, privatePreview),
        onSettings: (s) { setState(() { palette=s.palette; mode=s.mode; scale=s.scale; dense=s.dense; privatePreview=s.privatePreview; }); _save(); },
        colors: colors),
    );
  }
}
class SettingsState {
  final int palette; final ThemeMode mode; final double scale; final bool dense; final bool privatePreview;
  const SettingsState(this.palette, this.mode, this.scale, this.dense, this.privatePreview);
}
class HomeScreen extends StatefulWidget {
  final SettingsState settings;
  final ValueChanged<SettingsState> onSettings;
  final List<Color> colors;
  const HomeScreen({super.key, required this.settings, required this.onSettings, required this.colors});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  int tab=0;
  String query='';
  MessageCategory? filter;
  final demo = <MessageRecord>[
    MessageRecord(sender:'هنر مردمی', body:'به پیامیار خوش آمدید. این داده نمایشی است.', date:DateTime(2026,11,11,10)),
    MessageRecord(sender:'بانک نمونه', body:'واریز ۲۵۰,۰۰۰ تومان به حساب نمونه. پیام آزمایشی.', date:DateTime(2026,11,11,9)),
    MessageRecord(sender:'اپراتور', body:'بسته اینترنت شما فعال شد.', date:DateTime(2026,11,10)),
    MessageRecord(sender:'فروشگاه نمونه', body:'تخفیف ویژه امروز؛ تبلیغ آزمایشی.', date:DateTime(2026,11,9)),
  ];
  @override
  Widget build(BuildContext context) {
    final wide=MediaQuery.sizeOf(context).width>=760;
    final scheme=Theme.of(context).colorScheme;
    final pages=[_messages(),_security(),_insights(),_settings()];
    return Scaffold(
      appBar: AppBar(title: const Text('پیامیار'), actions:[Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Center(child: Text('نسخه آزمایشی',style:TextStyle(color:scheme.primary,fontSize:12))))]),
      body: Row(children:[
        if(wide) NavigationRail(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v), labelType:NavigationRailLabelType.all, destinations:const [
          NavigationRailDestination(icon:Icon(Icons.message_outlined),label:Text('پیام‌ها')),
          NavigationRailDestination(icon:Icon(Icons.security_outlined),label:Text('امنیت')),
          NavigationRailDestination(icon:Icon(Icons.bar_chart_outlined),label:Text('گزارش')),
          NavigationRailDestination(icon:Icon(Icons.tune),label:Text('شخصی‌سازی')),
        ]),
        Expanded(child:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:1020),child:pages[tab]))),
      ]),
      bottomNavigationBar:wide?null:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [
        NavigationDestination(icon:Icon(Icons.message_outlined),label:'پیام‌ها'),
        NavigationDestination(icon:Icon(Icons.shield_outlined),label:'امنیت'),
        NavigationDestination(icon:Icon(Icons.insights_outlined),label:'گزارش'),
        NavigationDestination(icon:Icon(Icons.palette_outlined),label:'ظاهر'),
      ]),
    );
  }
  Widget _messages() {
    final filtered=MessageLogic.search(demo,query).where((m)=>filter==null || MessageLogic.category(m)==filter).toList();
    return ListView(padding:const EdgeInsets.all(18),children:[
      Text('مدیریت پیام‌ها',style:Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height:8),
      const Text('برای حفظ حریم خصوصی، این نسخه فعلاً فقط پیام‌های نمونه را نشان می‌دهد.'),
      const SizedBox(height:16),
      TextField(onChanged:(v)=>setState(()=>query=v),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),border:OutlineInputBorder(),hintText:'جستجوی متن و فرستنده')),
      const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:5,children:[
        ChoiceChip(label:const Text('همه'),selected:filter==null,onSelected:(_)=>setState(()=>filter=null)),
        for(final c in MessageCategory.values) ChoiceChip(label:Text(_name(c)),selected:filter==c,onSelected:(_)=>setState(()=>filter=c)),
      ]),
      const SizedBox(height:10),
      for(final m in filtered) Card(child:ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal:16,vertical:widget.settings.dense?0:9),
        leading:CircleAvatar(child:Icon(_icon(MessageLogic.category(m)))),
        title:Text(m.sender),
        subtitle:Text(widget.settings.privatePreview?'متن پیام مخفی است':m.body,maxLines:2,overflow:TextOverflow.ellipsis),
        trailing:MessageLogic.suspicious(m.body)?const Icon(Icons.warning_amber_rounded,color:Colors.orange):null,
      )),
      if(filtered.isEmpty) const Padding(padding:EdgeInsets.all(25),child:Center(child:Text('پیامی مطابق جستجو نیست.'))),
    ]);
  }
  String _name(MessageCategory c) => switch(c) {
    MessageCategory.personal=>'شخصی',MessageCategory.banking=>'بانکی',
    MessageCategory.service=>'خدماتی',MessageCategory.advertising=>'تبلیغاتی',
  };
  IconData _icon(MessageCategory c) => switch(c){
    MessageCategory.personal=>Icons.person_outline,MessageCategory.banking=>Icons.account_balance_outlined,
    MessageCategory.service=>Icons.settings_outlined,MessageCategory.advertising=>Icons.campaign_outlined,
  };
  Widget _security()=>ListView(padding:const EdgeInsets.all(20),children:[
    Text('امنیت و حریم خصوصی',style:Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height:14),
    const Card(child:ListTile(leading:Icon(Icons.security),title:Text('تحلیل پیام‌های مشکوک'),subtitle:Text('در نسخه نمایشی، قواعد اولیه شناسایی وجود دارد؛ مدل هوش مصنوعی هنوز متصل نیست.'))),
    const Card(child:ListTile(leading:Icon(Icons.phonelink_lock),title:Text('اتصال گوشی و ویندوز'),subtitle:Text('تا آماده‌شدن جفت‌سازی رمزگذاری‌شده، همگام‌سازی غیرفعال است.'))),
    const Card(child:ListTile(leading:Icon(Icons.enhanced_encryption),title:Text('پشتیبان‌گیری امن'),subtitle:Text('این قابلیت در نسخه اجرایی بعدی ارزیابی و تکمیل خواهد شد.'))),
  ]);
  Widget _insights()=>ListView(padding:const EdgeInsets.all(20),children:[
    Text('گزارش مالی',style:Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height:12),
    const Card(child:ListTile(leading:Icon(Icons.account_balance_wallet_outlined),title:Text('گزارش تراکنش‌های بانکی'),subtitle:Text('پس از اتصال امن پیامک‌ها و تشخیص معتبر ریال/تومان فعال خواهد شد.'))),
    const Card(child:ListTile(leading:Icon(Icons.privacy_tip_outlined),title:Text('حریم خصوصی'),subtitle:Text('بدون اجازه شما هیچ پیام یا تراکنشی به وردپرس منتقل نمی‌شود.'))),
  ]);
  Widget _settings() {
    final s=widget.settings;
    void change({int? p,ThemeMode? m,double? sc,bool? d,bool? hide}) =>
      widget.onSettings(SettingsState(p??s.palette,m??s.mode,sc??s.scale,d??s.dense,hide??s.privatePreview));
    return ListView(padding:const EdgeInsets.all(18),children:[
      Text('شخصی‌سازی',style:Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height:16),
      const Text('رنگ اصلی رابط کاربری'),
      const SizedBox(height:12),
      Wrap(spacing:12,runSpacing:12,children:[
        for(int i=0;i<widget.colors.length;i++) Tooltip(message:'رنگ ${i+1}',child:InkWell(onTap:()=>change(p:i),child:CircleAvatar(backgroundColor:widget.colors[i],radius:23,child:i==s.palette?const Icon(Icons.check,color:Colors.white):null))),
      ]),
      const SizedBox(height:24),
      const Text('حالت نمایش'),
      SegmentedButton<ThemeMode>(segments:const [
        ButtonSegment(value:ThemeMode.system,label:Text('سیستم')),
        ButtonSegment(value:ThemeMode.light,label:Text('روشن')),
        ButtonSegment(value:ThemeMode.dark,label:Text('تاریک')),
      ],selected:{s.mode},onSelectionChanged:(v)=>change(m:v.first)),
      const SizedBox(height:20),
      Text('اندازه نوشته‌ها: ${(s.scale*100).round()}٪'),
      Slider(value:s.scale.clamp(.85,1.3),min:.85,max:1.3,divisions:9,onChanged:(v)=>change(sc:v)),
      SwitchListTile(title:const Text('چیدمان فشرده'),value:s.dense,onChanged:(v)=>change(d:v)),
      SwitchListTile(title:const Text('مخفی‌کردن پیش‌نمایش پیام'),value:s.privatePreview,onChanged:(v)=>change(hide:v)),
      const SizedBox(height:15),
      const Text('تم‌های فیروزه‌ای، لاجوردی، بنفش، زرشکی، سبز و طلایی — الهام‌گرفته از هویت هنر مردمی.'),
    ]);
  }
}
