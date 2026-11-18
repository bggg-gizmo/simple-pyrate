package com.bggg.simplepyrate;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.*;
import android.provider.DocumentsContract;
import android.text.InputType;
import android.text.TextUtils;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.util.*;

public final class MainActivity extends Activity {
    static final int INK=0xff0b171e,PANEL=0xe7102027,LINE=0xff325058,GOLD=0xffe6b876,PALE=0xfff2e9d5,TEAL=0xffa6d4c4,MUTED=0xff9ab7b8;
    static final String WALLET="8AEyf8SfkYx6sHrLsp8aSAXrS8r9BZmnBfA6US9taa4mWpPXMNitipudPXU1MynA2mYHEXTsRZJik45gFjRsmeJ6HxRBEvn";
    private static final String[] HEIGHTS={"Best available","2160p (4K)","1440p","1080p","720p","480p","360p"};
    private static final int[] RES={0,2160,1440,1080,720,480,360};
    private static final String[] QUALITIES={"128K","192K","256K","320K","0"};
    private static final int FOLDER=22,COOKIES=23;
    private final DeckState.Receiver receiver=this::refresh;
    private DeckState deck;
    private FrameLayout root;
    private LinearLayout layout,columns,dock,compose,rail,queueRows,optionsVideo,optionsAudio,optionsCaptions,advanced;
    private ScrollView dockScroll;
    private View sceneWindow;
    private Dialog queueDialog;
    private TextView voyageSummary;
    private Button queueSummary,sourceAccess;
    private ProgressBar deckProgress;
    private final Rect sceneRect=new Rect();
    private EditText input,languages;
    private CheckBox mp4,mp3,transcript,automatic;
    private Spinner scope,resolution,quality,captionFormat;
    private TextView status,headline,detail,folderText,queueCount,accessCaption,accessDialogStatus,wizardFolder,settingsNow;
    private EditText tokenEditor;
    private SavedAccess savedAccess;
    private ProgressBar progress;
    private Button queue,stop,clear,filesButton,openFolderButton;
    private Uri destination;
    private Dialog wizard;
    private LinearLayout wizardBody;
    private int wizardPage;
    private String wizardStatus="";
    private boolean dual;
    private int lastQueueRows=-1;
    private long lastQueueRefresh=0L;
    private final HashMap<DeckState.Job,String> rowState=new HashMap<>();
    @Override public void onCreate(Bundle saved){
        super.onCreate(saved);deck=DeckState.get(this);savedAccess=new SavedAccess(this);
        getWindow().setStatusBarColor(INK);getWindow().setNavigationBarColor(INK);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE|WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
        String uri=deck.prefs.getString("destination","");destination=uri.isEmpty()?null:Uri.parse(uri);
        build();layout(getResources().getConfiguration());
        if(saved!=null)input.setText(saved.getString("source",""));
        if(!deck.prefs.getBoolean("setup",false))root.post(this::shipyard);
    }
    @Override public void onSaveInstanceState(Bundle b){super.onSaveInstanceState(b);b.putString("source",input.getText().toString());}
    @Override protected void onStart(){super.onStart();deck.view=receiver;deck.audio.foreground(true);refresh();}
    @Override protected void onStop(){if(deck.view==receiver)deck.view=null;deck.audio.foreground(false);super.onStop();}
    @Override public void onConfigurationChanged(Configuration c){super.onConfigurationChanged(c);layout(c);}
    private void build(){
        root=new FrameLayout(this);
        root.setBackgroundColor(INK);
        if(deck.voyage.getParent() instanceof ViewGroup)((ViewGroup)deck.voyage.getParent()).removeView(deck.voyage);
        root.addView(deck.voyage,new FrameLayout.LayoutParams(-1,-1));
        layout=vertical();layout.setFocusableInTouchMode(true);root.addView(layout,new FrameLayout.LayoutParams(-1,-1));
        layout.setOnApplyWindowInsetsListener((v,i)->{
            if(Build.VERSION.SDK_INT>=30){
                android.graphics.Insets system=i.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());
                android.graphics.Insets ime=i.getInsets(WindowInsets.Type.ime());
                v.setPadding(system.left,system.top,system.right,Math.max(system.bottom,ime.bottom));
            }else v.setPadding(i.getSystemWindowInsetLeft(),i.getSystemWindowInsetTop(),i.getSystemWindowInsetRight(),i.getSystemWindowInsetBottom());
            return i;
        });
        if(Build.VERSION.SDK_INT>=30)getWindow().setDecorFitsSystemWindows(false);
        else getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        layout.addView(header());
        columns=vertical();
        layout.addView(columns,new LinearLayout.LayoutParams(-1,0,1));
        sceneWindow=new View(this);sceneWindow.setTag("pyrate-scene");sceneWindow.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        root.getViewTreeObserver().addOnGlobalLayoutListener(()->{
            if(sceneWindow.getWidth()==0||sceneWindow.getHeight()==0){deck.voyage.viewport(new Rect());return;}
            sceneWindow.getDrawingRect(sceneRect);root.offsetDescendantRectToMyCoords(sceneWindow,sceneRect);
            deck.voyage.viewport(sceneRect);
        });
        dock=vertical();dock.setPadding(dp(10),0,dp(10),dp(7));
        dockScroll=new ScrollView(this);dockScroll.setFillViewport(false);
        dock.addView(dockScroll,new LinearLayout.LayoutParams(-1,0,1));
        compose=panel();compose.setPadding(dp(12),dp(7),dp(12),dp(5));rail=vertical();
        dockScroll.addView(compose,new ScrollView.LayoutParams(-1,-2));
        makeCompose();makeRail();makeQuickActions();
        setContentView(root);layout.requestFocus();root.requestApplyInsets();
    }
    private View header(){
        LinearLayout bar=horizontal();bar.setGravity(Gravity.CENTER_VERTICAL);bar.setPadding(dp(12),dp(6),dp(10),dp(6));bar.setBackgroundColor(0xe9102027);
        ImageView icon=new ImageView(this);icon.setImageResource(R.mipmap.pyrate_launcher);icon.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        bar.addView(icon,new LinearLayout.LayoutParams(dp(35),dp(35)));
        LinearLayout brand=vertical();brand.setPadding(dp(7),0,dp(4),0);bar.addView(brand,new LinearLayout.LayoutParams(0,-2,1));
        TextView name=label("SIMPLE PYRATE",19,GOLD);name.setTypeface(Typeface.create("serif",Typeface.BOLD));name.setLetterSpacing(.08f);name.setMaxLines(1);brand.addView(name);
        TextView version=kicker("V2.6.3  /  BGGG  ·  EST. 2020");version.setTextSize(9);brand.addView(version);
        Button configure=button("Settings",false,()->settings());bar.addView(configure,new LinearLayout.LayoutParams(-2,dp(44)));
        Button tools=button("Shipyard",false,()->shipyard());addH(bar,tools,0,6);
        return bar;
    }
    private void makeCompose(){
        TextView inputCaption=kicker("NEW HAUL  /  SOURCE LINKS");
        addTop(compose,inputCaption,2);
        input=entry("Paste one video, playlist or channel URL per line");input.setTag("pyrate-source");
        input.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_FLAG_MULTI_LINE|InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        input.setMinLines(1);input.setMaxLines(2);input.setMinHeight(dp(48));input.setGravity(Gravity.TOP|Gravity.START);input.setTextSize(14);
        compose.addView(input,new LinearLayout.LayoutParams(-1,-2));
        advanced=dialogBody();
        caption(advanced,"Download scope");
        scope=spin("Single item per link","Whole playlist or channel");
        scope.setSelection(deck.prefs.getInt("scope",0)==0?0:1);
        advanced.addView(scope,new LinearLayout.LayoutParams(-1,dp(48)));
        LinearLayout cargo=horizontal();compose.addView(cargo,new LinearLayout.LayoutParams(-1,-2));
        mp4=check("MP4",deck.prefs.getBoolean("mp4",true));
        mp3=check("MP3",deck.prefs.getBoolean("mp3",false));
        transcript=check("Transcript",deck.prefs.getBoolean("transcript",false));
        addH(cargo,mp4,1,0);addH(cargo,mp3,1,6);addH(cargo,transcript,1,6);
        optionsVideo=vertical();advanced.addView(optionsVideo);caption(optionsVideo,"Video quality");
        resolution=spin(HEIGHTS);resolution.setSelection(safeIndex(deck.prefs.getInt("height",0),HEIGHTS.length));optionsVideo.addView(resolution,new LinearLayout.LayoutParams(-1,dp(45)));
        optionsAudio=vertical();advanced.addView(optionsAudio);caption(optionsAudio,"MP3 quality");
        quality=spin("128 kbps","192 kbps","256 kbps","320 kbps","Best (VBR)");quality.setSelection(safeIndex(deck.prefs.getInt("quality",2),QUALITIES.length));optionsAudio.addView(quality,new LinearLayout.LayoutParams(-1,dp(45)));
        optionsCaptions=vertical();advanced.addView(optionsCaptions);caption(optionsCaptions,"Transcript options");
        languages=entry("en, de, pt-BR, or all");languages.setSingleLine(true);languages.setText(deck.prefs.getString("languages","en"));optionsCaptions.addView(languages);
        captionFormat=spin("SRT + plain text (TXT)","SRT captions","Plain text (TXT)");
        captionFormat.setSelection(safeIndex(deck.prefs.getInt("captionFormat",0),3));optionsCaptions.addView(captionFormat);
        automatic=check("Use automatic captions if available",deck.prefs.getBoolean("auto",true));optionsCaptions.addView(automatic);
        for(CheckBox box:new CheckBox[]{mp4,mp3,transcript})box.setOnCheckedChangeListener((v,b)->cargoOptions());
        cargoOptions();
        caption(advanced,"Save to");
        LinearLayout pathRow=horizontal();pathRow.setGravity(Gravity.CENTER_VERTICAL);
        folderText=label(folderName(),13,TEAL);folderText.setMaxLines(2);pathRow.addView(folderText,new LinearLayout.LayoutParams(0,-2,1));
        addH(pathRow,button("Browse",false,this::chooseFolder),0,8);advanced.addView(pathRow);
        accessCaption=label("Source access not set",11,MUTED);
        accessCaption.setPadding(0,dp(6),0,dp(2));advanced.addView(accessCaption);
        addTop(advanced,button("Source access",false,this::accessSettings),6);
    }
    private void makeQuickActions(){
        LinearLayout actions=horizontal();
        actions.setGravity(Gravity.CENTER_VERTICAL);actions.setBackgroundColor(INK);
        queue=button("Download",true,this::submit);queue.setTag("pyrate-download");
        addH(actions,queue,3,0);
        addH(actions,button("Options",false,this::downloadOptions),2,6);
        sourceAccess=button("PO token",false,this::quickAccess);sourceAccess.setTag("pyrate-token");
        sourceAccess.setContentDescription("Source access, YouTube PO token and cookies");
        addH(actions,sourceAccess,2,6);
        addTop(dock,actions,5);
        LinearLayout activeRow=horizontal();activeRow.setGravity(Gravity.CENTER_VERTICAL);
        activeRow.setBackgroundColor(INK);
        voyageSummary=label("",12,TEAL);voyageSummary.setMaxLines(2);voyageSummary.setEllipsize(TextUtils.TruncateAt.END);
        activeRow.addView(voyageSummary,new LinearLayout.LayoutParams(0,-2,1));
        queueSummary=button("Queue",false,this::showQueue);
        addH(activeRow,queueSummary,0,7);
        addTop(dock,activeRow,4);
        deckProgress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);
        deckProgress.setMax(100);deckProgress.setContentDescription("Active haul progress");
        deckProgress.setProgressTintList(ColorStateList.valueOf(GOLD));
        deckProgress.setIndeterminateTintList(ColorStateList.valueOf(GOLD));
        dock.addView(deckProgress,new LinearLayout.LayoutParams(-1,dp(8)));
    }
    private void downloadOptions(){
        if(advanced.getParent() instanceof ViewGroup)((ViewGroup)advanced.getParent()).removeView(advanced);
        cargoOptions();Dialog d=dialog("Download options",advanced);d.show();size(d);
    }
    private void showQueue(){
        if(queueDialog!=null&&queueDialog.isShowing())return;
        if(rail.getParent() instanceof ViewGroup)((ViewGroup)rail.getParent()).removeView(rail);
        queueDialog=dialog("Voyage control",rail);
        queueDialog.setOnDismissListener(d->queueDialog=null);
        refresh();renderQueue();queueDialog.show();size(queueDialog);
    }
    private void makeRail(){
        LinearLayout active=panel();
        LinearLayout.LayoutParams spacer=new LinearLayout.LayoutParams(-1,-2);spacer.bottomMargin=dp(12);
        rail.addView(active,spacer);
        active.addView(kicker("02  /  VOYAGE CONTROL"));
        status=label("",11,TEAL);status.setTypeface(Typeface.MONOSPACE);status.setPadding(0,dp(11),0,0);active.addView(status);
        headline=title("",23);headline.setMaxLines(2);headline.setEllipsize(TextUtils.TruncateAt.END);active.addView(headline);
        progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);progress.setMax(100);
        progress.setProgressTintList(ColorStateList.valueOf(GOLD));progress.setIndeterminateTintList(ColorStateList.valueOf(GOLD));
        progress.setProgressBackgroundTintList(ColorStateList.valueOf(0xff29424a));progress.setContentDescription("Haul progress");
        active.addView(progress,new LinearLayout.LayoutParams(-1,dp(16)));
        detail=label("",13,MUTED);detail.setMaxLines(3);active.addView(detail);
        stop=button("Stop active",false,()->deck.stop());addTop(active,stop,8);
        LinearLayout manifest=panel();rail.addView(manifest);
        LinearLayout first=horizontal();first.setGravity(Gravity.CENTER_VERTICAL);manifest.addView(first);
        first.addView(title("Voyage queue",23),new LinearLayout.LayoutParams(0,-2,1));queueCount=kicker("0 WAITING");first.addView(queueCount);
        queueRows=vertical();manifest.addView(queueRows,new LinearLayout.LayoutParams(-1,-2));
        LinearLayout actions=horizontal();manifest.addView(actions);
        clear=button("Clear finished",false,()->deck.clearFinished());addH(actions,clear,1,0);
        addH(actions,button("Ship’s log",false,this::showLog),1,6);
        LinearLayout fileActions=horizontal();manifest.addView(fileActions);
        openFolderButton=button("Open save folder",false,this::openFolder);addH(fileActions,openFolderButton,1,0);
        filesButton=button("Saved files (0)",false,this::savedFiles);addH(fileActions,filesButton,1,6);
        TextView footer=label("THE BACKGROUND GREMLIN GROUP  ·  EST. 2020\nDeveloping unique tools for unique individuals",11,MUTED);
        footer.setPadding(dp(12),dp(12),dp(12),dp(7));rail.addView(footer);
    }
    private void layout(Configuration c){
        dual=c.orientation==Configuration.ORIENTATION_LANDSCAPE;
        columns.removeAllViews();columns.setOrientation(dual?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL);
        if(dual){
            columns.addView(sceneWindow,new LinearLayout.LayoutParams(0,-1,1.12f));
            columns.addView(dock,new LinearLayout.LayoutParams(0,-1,1f));
        }else{
            columns.addView(sceneWindow,new LinearLayout.LayoutParams(-1,0,1f));
            columns.addView(dock,new LinearLayout.LayoutParams(-1,-2));
        }
        dockScroll.setLayoutParams(dual?new LinearLayout.LayoutParams(-1,0,1):
                new LinearLayout.LayoutParams(-1,dp(c.fontScale>1.25?166:130)));
    }
    private void cargoOptions(){
        optionsVideo.setVisibility(mp4.isChecked()?View.VISIBLE:View.GONE);
        optionsAudio.setVisibility(mp3.isChecked()?View.VISIBLE:View.GONE);
        optionsCaptions.setVisibility(transcript.isChecked()?View.VISIBLE:View.GONE);
    }
    private void submit(){
        try{
            List<String> modes=new ArrayList<>();
            if(mp4.isChecked())modes.add("MP4");if(mp3.isChecked())modes.add("MP3");if(transcript.isChecked())modes.add("Transcript");
            if(modes.isEmpty())throw new IllegalArgumentException("Choose a cargo format.");
            Set<String> links=new LinkedHashSet<>();
            for(String line:input.getText().toString().split("\\r?\\n"))if(!line.trim().isEmpty())links.add(Access.link(line.trim()).toString());
            if(links.isEmpty())throw new IllegalArgumentException("Paste at least one source link.");
            if(links.size()>300)throw new IllegalArgumentException("Queue up to 300 source links at once.");
            String lang=modes.contains("Transcript")?languages.getText().toString():"en";
            int height=resolution.getSelectedItemPosition(),q=quality.getSelectedItemPosition(),sc=scope.getSelectedItemPosition();
            List<CargoRunner.Settings> requests=new ArrayList<>();
            for(String url:links)requests.add(new CargoRunner.Settings(url,modes,sc==1,RES[height],QUALITIES[q],lang,captionFormat.getSelectedItemPosition()!=1,captionFormat.getSelectedItemPosition()!=2,automatic.isChecked(),destination));
            deck.prefs.edit().putInt("scope",sc).putBoolean("mp4",mp4.isChecked()).putBoolean("mp3",mp3.isChecked())
                .putBoolean("transcript",transcript.isChecked()).putInt("height",height).putInt("quality",q)
                .putString("languages",languages.getText().toString()).putInt("captionFormat",captionFormat.getSelectedItemPosition()).putBoolean("auto",automatic.isChecked()).apply();
            ((android.view.inputmethod.InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(input.getWindowToken(),0);
            input.clearFocus();deck.beginQueue(this,requests);
            if(Build.VERSION.SDK_INT>=33&&!deck.prefs.getBoolean("askedNotifications",false)){
                deck.prefs.edit().putBoolean("askedNotifications",true).apply();
                if(checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED)
                    requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},24);
            }
        }catch(Exception e){message("Check your course",e.getMessage());}
    }
    private void refresh(){
        if(status==null)return;
        boolean indeterminate=deck.active!=null&&deck.percent<0;
        if(queueDialog!=null){
            setChanged(status,deck.state.toUpperCase(Locale.ROOT));
            setChanged(headline,deck.title);setChanged(detail,deck.detail);
            if(progress.isIndeterminate()!=indeterminate)progress.setIndeterminate(indeterminate);
            if(!indeterminate&&progress.getProgress()!=Math.max(0,deck.percent))progress.setProgress(Math.max(0,deck.percent),true);
            stop.setEnabled(deck.active!=null);clear.setEnabled(deck.rows.size()>deck.waiting()+(deck.active==null?0:1));
            setChanged(queueCount,deck.waiting()+" WAITING");
            setChanged(filesButton,"Saved files ("+deck.files.size()+")");filesButton.setEnabled(!deck.files.isEmpty());
        }
        if(deckProgress.isIndeterminate()!=indeterminate)deckProgress.setIndeterminate(indeterminate);
        if(!indeterminate&&deckProgress.getProgress()!=Math.max(0,deck.percent))deckProgress.setProgress(Math.max(0,deck.percent),true);
        deckProgress.setVisibility(deck.active!=null?View.VISIBLE:View.INVISIBLE);
        String summary=deck.state+(deck.active!=null&&deck.percent>=0?" · "+deck.percent+"%":"");
        if("Resolving source".equals(deck.state)&&deck.active!=null)summary+=" · "+deck.detail;
        if(!TextUtils.equals(voyageSummary.getText(),summary))voyageSummary.setText(summary);
        String queueText=deck.waiting()>0?"Queue ("+deck.waiting()+")":"Queue";
        if(!TextUtils.equals(queueSummary.getText(),queueText))queueSummary.setText(queueText);
        String accessText=!deck.access.po.isEmpty()?"Token on":deck.access.cookies!=null?"Cookies on":savedAccess.exists()?"Use sign-in":"PO token";
        if(!TextUtils.equals(sourceAccess.getText(),accessText)){
            sourceAccess.setText(accessText);sourceAccess.setContentDescription("Source access. "+accessText);
        }

        queue.setEnabled(!deck.checking);
        setChanged(accessCaption,deck.access.active()?"Source access configured for this session":"Source access not set");
        if(queueDialog!=null&&(lastQueueRows!=deck.rows.size()||SystemClock.uptimeMillis()-lastQueueRefresh>=250)){
            boolean changed=lastQueueRows!=deck.rows.size();
            for(DeckState.Job j:deck.rows)changed|=!Objects.equals(rowState.get(j),j.state+"|"+j.detail);
            if(changed)renderQueue();
        }
    }
    private void renderQueue(){
        lastQueueRows=deck.rows.size();lastQueueRefresh=SystemClock.uptimeMillis();rowState.clear();
        queueRows.removeAllViews();
        if(deck.rows.isEmpty()){
            TextView empty=label("No hauls in the queue.",13,MUTED);empty.setPadding(0,dp(13),0,dp(13));queueRows.addView(empty);return;
        }
        for(DeckState.Job j:deck.rows)rowState.put(j,j.state+"|"+j.detail);
        int from=Math.max(0,deck.rows.size()-8);
        if(from>0)addTop(queueRows,button("All "+deck.rows.size()+" hauls",false,this::allHauls),4);
        for(int i=from;i<deck.rows.size();i++){
            DeckState.Job job=deck.rows.get(i);rowState.put(job,job.state+"|"+job.detail);
            TextView row=label(job.state+"  ·  "+host(job.options.url)+"  ·  "+TextUtils.join(" / ",job.options.modes)+(job.detail.isEmpty()?"":"\n"+job.detail),13,TEAL);
            row.setPadding(dp(9),dp(8),dp(9),dp(8));row.setGravity(Gravity.CENTER_VERTICAL);
            row.setMinHeight(dp(45));row.setBackground(box(0xff112830,LINE,7));row.setOnClickListener(v->jobActions(job));
            addTop(queueRows,row,5);
        }
    }
    private void allHauls(){
        LinearLayout b=dialogBody();Dialog d=dialog("All hauls",b);
        for(DeckState.Job j:deck.rows)addTop(b,button(j.state+" · "+host(j.options.url),false,()->{d.dismiss();jobActions(j);}),5);
        addTop(b,button("Close",true,d::dismiss),9);d.show();size(d);
    }
    private void jobActions(DeckState.Job j){
        if(j==deck.active){message("Active haul",j.detail.isEmpty()?deck.detail:j.detail);return;}
        if(j.state.equals("Queued"))new AlertDialog.Builder(this).setTitle("Queued haul").setMessage(j.options.url).setNegativeButton("Keep",null).setPositiveButton("Remove",(d,w)->deck.remove(j)).show();
        else new AlertDialog.Builder(this).setTitle(j.state).setMessage(j.options.url+"\n\n"+j.detail).setNeutralButton("Close",null)
            .setNegativeButton("Remove",(d,w)->deck.remove(j)).setPositiveButton("Retry",(d,w)->deck.retry(this,j)).show();
    }
    private void showLog(){
        LinearLayout b=dialogBody();TextView text=label(deck.logs.isEmpty()?"No entries yet.":TextUtils.join("\n",deck.logs),12,TEAL);
        text.setTextIsSelectable(true);text.setTypeface(Typeface.MONOSPACE);b.addView(text);
        Dialog d=dialog("Ship’s log",b);addTop(b,button("Close",true,d::dismiss),13);d.show();size(d);
    }
    private void savedFiles(){
        LinearLayout b=dialogBody();Dialog d=dialog("Saved files",b);
        for(CargoRunner.Saved f:deck.files)addTop(b,button(f.name,false,()->viewFile(f)),4);
        addTop(b,button("Close",true,d::dismiss),12);d.show();size(d);
    }
    private void viewFile(CargoRunner.Saved saved){
        String name=saved.name.toLowerCase(Locale.ROOT);
        String type=name.endsWith(".mp4")?"video/mp4":name.endsWith(".mp3")?"audio/mpeg":"text/plain";
        try{startActivity(new Intent(Intent.ACTION_VIEW).setDataAndType(saved.uri,type).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION));}
        catch(ActivityNotFoundException e){message("File saved","No app on this device can open that format. Find it in your save folder.");}
    }
    private void openFolder(){
        try{
            if(destination==null)startActivity(new Intent(DownloadManager.ACTION_VIEW_DOWNLOADS));
            else {
                Uri doc=DocumentsContract.buildDocumentUriUsingTree(destination,DocumentsContract.getTreeDocumentId(destination));
                Intent i=new Intent(Intent.ACTION_VIEW).setDataAndType(doc,DocumentsContract.Document.MIME_TYPE_DIR).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                startActivity(i);
            }
        }catch(Exception e){message("Save folder",folderName()+"\nOpen Files to browse this location.");}
    }
    private void settings(){
        LinearLayout b=dialogBody();Dialog d=dialog("Settings",b);
        addTop(b,button("Support the crew · XMR donation",false,this::donationSettings),0);
        b.addView(kicker("01  /  SOUND DECK"));
        CheckBox fx=check("Port sound effects and ship bells",deck.audio.fx());b.addView(fx);
        fx.setOnCheckedChangeListener((view,on)->{deck.prefs.edit().putBoolean("effects",on).apply();deck.audio.preferences();});
        CheckBox ocean=check("Sea sound",deck.audio.sea());b.addView(ocean);
        ocean.setOnCheckedChangeListener((view,on)->{deck.prefs.edit().putBoolean("sea",on).apply();deck.audio.preferences();});
        CheckBox motion=check("Motion",deck.prefs.getBoolean("motion",true));b.addView(motion);
        motion.setOnCheckedChangeListener((view,on)->{deck.prefs.edit().putBoolean("motion",on).apply();deck.voyage.motion(on);});
        caption(b,"Music playlist");
        Spinner playlist=spin(AudioDeck.LISTS);playlist.setSelection(deck.audio.playlist());b.addView(playlist);
        settingsNow=label(deck.audio.trackTitle(),12,TEAL);b.addView(settingsNow);
        playlist.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){
            @Override public void onItemSelected(AdapterView<?> parent,View v,int p,long id){
                if(deck.audio.playlist()!=p)deck.audio.select(p);settingsNow.setText(deck.audio.trackTitle());
            }
            @Override public void onNothingSelected(AdapterView<?> parent){}
        });
        volume(b,"Music volume","musicVolume",deck.audio.musicVolume());volume(b,"Port sound effects volume","fxVolume",deck.audio.effectsVolume());
        LinearLayout audition=horizontal();b.addView(audition);
        addH(audition,button("Next track",false,()->{deck.audio.next();settingsNow.setText(deck.audio.trackTitle());}),1,0);
        addH(audition,button("Preview cannon",false,()->deck.audio.raid(0)),1,6);
        addTop(b,kicker("02  /  SOURCE ACCESS"),14);
        b.addView(label("Optional yt-dlp tokens and a cookies.txt export for your own signed-in session.",14,MUTED));
        addTop(b,button("Source access",false,this::accessSettings),6);
        addTop(b,button("Open-source notices",false,this::notices),7);
        addTop(b,button("Close",true,d::dismiss),12);d.show();size(d);
    }
    private void donationSettings(){
        LinearLayout b=dialogBody();Dialog d=dialog("Support the crew",b);
        b.addView(label("Monero donation address for the Background Gremlin Group",14,TEAL));
        TextView addr=label(WALLET,12,TEAL);addr.setTypeface(Typeface.MONOSPACE);addr.setTextIsSelectable(true);b.addView(addr);
        LinearLayout donation=horizontal();b.addView(donation);
        addH(donation,button("Copy XMR address",false,()->{
            ((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("BGGG donation address",WALLET));
            Toast.makeText(this,"Monero address copied.",Toast.LENGTH_SHORT).show();
        }),1,0);
        addH(donation,button("Open wallet",false,()->openUri("monero:"+WALLET,"No Monero wallet can open this link.")),1,6);
        addTop(b,button("Close",true,d::dismiss),12);d.show();size(d);
    }
    private void notices(){
        try{
            LinearLayout b=dialogBody();Dialog d=dialog("Open-source notices",b);
            for(String name:getAssets().list("notices"))addTop(b,button(name,false,()->{
                try(InputStream in=getAssets().open("notices/"+name);ByteArrayOutputStream out=new ByteArrayOutputStream()){
                    RuntimeTools.copy(in,out,1024*1024);LinearLayout license=dialogBody();TextView copy=label(out.toString("UTF-8"),13,TEAL);
                    copy.setTextIsSelectable(true);license.addView(copy);Dialog text=dialog(name,license);text.show();size(text);
                }catch(IOException e){message("Notice unavailable",e.getMessage());}
            }),5);
            addTop(b,button("Close",true,d::dismiss),12);d.show();size(d);
        }catch(IOException e){message("Notices unavailable",e.getMessage());}
    }
    private void quickAccess(){
        if(!deck.access.active()&&savedAccess.exists()){loadSavedAccess(null);return;}
        accessSettings();
    }
    private void loadSavedAccess(Dialog dialog){
        try{
            deck.access=savedAccess.load();deck.notifyView();
            Toast.makeText(this,"Saved source access is on for new hauls.",Toast.LENGTH_SHORT).show();
            if(dialog!=null)dialog.dismiss();
        }catch(Exception e){message("Saved sign-in unavailable","Open Settings → Source access to import or replace your sign-in.");}
    }
    private void accessSettings(){
        LinearLayout b=dialogBody();Dialog d=dialog("Source access",b);
        b.addView(label("Use credentials for an account you control and content the source allows that account to access. Android does not share sign-in cookies from other apps. A PO token is not a sign-in credential.",14,TEAL));
        if(savedAccess.exists())addTop(b,button("Use saved sign-in",true,()->loadSavedAccess(d)),8);
        caption(b,"YouTube PO token");
        b.addView(label("Paste the full client.context+token value. Multiple values are comma-separated. Saved credentials apply to new hauls.",12,MUTED));
        tokenEditor=entry("client.context+token");
        tokenEditor.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD|InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        tokenEditor.setSingleLine(true);tokenEditor.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS);tokenEditor.setText(deck.access.po);b.addView(tokenEditor);
        accessDialogStatus=label("",12,MUTED);addTop(b,accessDialogStatus,8);credentialStatus();
        addTop(b,button("Import cookies.txt",false,()->{
            try{deck.access=new Access(tokenEditor.getText().toString(),deck.access.cookies);launchCookies();}
            catch(Exception e){message("Check source access",e.getMessage());}
        }),7);
        addTop(b,button("Clear session credentials",false,()->{
            deck.access=new Access("",null);tokenEditor.setText("");credentialStatus();deck.notifyView();
        }),5);
        addTop(b,button("Remember on this device",false,()->{
            try{
                Access access=new Access(tokenEditor.getText().toString(),deck.access.cookies);
                savedAccess.save(access);deck.access=access;deck.notifyView();
                Toast.makeText(this,"Source access saved securely on this device.",Toast.LENGTH_SHORT).show();d.dismiss();
            }catch(Exception e){message("Could not save source access",e instanceof IllegalArgumentException?e.getMessage():"Import cookies or enter a token first. The device must also support secure storage.");}
        }),6);
        if(savedAccess.exists())addTop(b,button("Forget saved sign-in",false,()->{
            try{
                savedAccess.clear();deck.access=new Access("",null);deck.notifyView();d.dismiss();
            }catch(Exception e){message("Saved sign-in","Could not clear saved source access.");}
        }),5);
        addTop(b,button("Save for this session",true,()->{
            try{deck.access=new Access(tokenEditor.getText().toString(),deck.access.cookies);deck.notifyView();d.dismiss();}
            catch(Exception e){message("Check source access",e.getMessage());}
        }),10);
        d.setOnDismissListener(x->{tokenEditor=null;accessDialogStatus=null;});d.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);d.show();size(d);
    }
    private void launchCookies(){
        Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*");
        startActivityForResult(i,COOKIES);
    }
    private void credentialStatus(){if(accessDialogStatus!=null)accessDialogStatus.setText(deck.access.cookies==null?"No cookie file loaded. Session credentials clear on restart unless you choose to remember them.":"Cookie file loaded for this session. Already queued hauls retain their credential snapshot.");}
    private void chooseFolder(){
        Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        try{startActivityForResult(i,FOLDER);}catch(ActivityNotFoundException e){message("Save folder","Android’s folder picker is not installed. Downloads / Simple Pyrate is available.");}
    }
    private String folderName(){
        if(destination==null)return "Downloads / Simple Pyrate";
        try{return DocumentsContract.getTreeDocumentId(destination).replaceFirst("(?i)^primary:","On device / ");}catch(Exception e){return "Selected folder";}
    }
    private void folderDisplay(){folderText.setText(folderName());if(wizardFolder!=null)wizardFolder.setText(folderName());}
    @Override protected void onActivityResult(int req,int result,Intent data){
        super.onActivityResult(req,result,data);
        if(result!=RESULT_OK||data==null||data.getData()==null)return;
        Uri uri=data.getData();
        try{
            if(req==FOLDER){
                int flags=data.getFlags()&(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                if((flags&Intent.FLAG_GRANT_WRITE_URI_PERMISSION)==0)throw new IOException("Pick a folder with write access.");
                getContentResolver().takePersistableUriPermission(uri,flags);destination=uri;
                deck.prefs.edit().putString("destination",destination.toString()).apply();folderDisplay();
            }else if(req==COOKIES){
                try(InputStream in=getContentResolver().openInputStream(uri);ByteArrayOutputStream out=new ByteArrayOutputStream()){
                    if(in==null)throw new IOException("Could not open the selected file.");
                    RuntimeTools.copy(in,out,1024*1024);
                    deck.access=new Access(deck.access.po,out.toByteArray());credentialStatus();deck.notifyView();
                }
            }
        }catch(Exception e){message(req==COOKIES?"Cookie file not imported":"Folder not selected",e.getMessage());}
    }
    private void shipyard(){
        if(wizard!=null&&wizard.isShowing())return;
        wizardPage=0;wizardStatus="";
        wizardBody=dialogBody();
        wizard=dialog("Shipyard",wizardBody);
        wizard.setOnDismissListener(d->{wizard=null;wizardFolder=null;});
        wizardStep();wizard.show();size(wizard);
    }
    private void wizardStep(){
        if(wizardBody==null)return;wizardBody.removeAllViews();wizardFolder=null;
        wizardBody.addView(kicker("0"+(wizardPage+1)+"  /  "+(wizardPage==0?"WELCOME ABOARD":wizardPage==1?"SAVE FOLDER":wizardPage==2?"BUNDLED TOOLS":"READY TO SAIL")));
        if(wizardPage==0){
            wizardBody.addView(title("Welcome to Simple Pyrate",25));
            wizardBody.addView(label("Let’s set up your ship.",16,TEAL));
            Voyage artwork=new Voyage(this,null);artwork.motion(false);artwork.artworkOnly();
            LinearLayout.LayoutParams shot=new LinearLayout.LayoutParams(-1,dp(107));shot.topMargin=dp(12);shot.bottomMargin=dp(8);wizardBody.addView(artwork,shot);
            wizardBody.addView(label("Choose where to save your cargo. Your download and conversion tools are already aboard.",14,MUTED));
        }else if(wizardPage==1){
            wizardBody.addView(title("Where should cargo go?",25));wizardFolder=label(folderName(),15,TEAL);wizardBody.addView(wizardFolder);
            addTop(wizardBody,button("Choose folder",false,this::chooseFolder),9);
            addTop(wizardBody,button("Use Downloads",false,()->{destination=null;deck.prefs.edit().remove("destination").apply();folderDisplay();}),6);
        }else if(wizardPage==2){
            wizardBody.addView(title("Tools on board",25));
            wizardBody.addView(label("Python, yt-dlp, QuickJS, FFmpeg and FFprobe are included. Update yt-dlp here. Native tool updates come with a signed Simple Pyrate APK.",14,TEAL));
            addTop(wizardBody,label(wizardStatus.isEmpty()?"Run the check to see the installed versions.":wizardStatus,12,MUTED),7);
            addTop(wizardBody,button("Check bundled tools",false,()->wizardCheck(false)),7);
            addTop(wizardBody,button("Update yt-dlp",false,()->wizardCheck(true)),5);
            addTop(wizardBody,button("Simple Pyrate releases",false,()->openUri("https://github.com/bggg-gizmo/simple-pyrate/releases","No browser can open the release page.")),5);
        }else{
            wizardBody.addView(title("You’re ready to sail",25));
            wizardBody.addView(label("Paste a source link, choose MP4, MP3 or transcripts, and tap Download for your first haul.",14,TEAL));
        }
        LinearLayout next=horizontal();next.setPadding(0,dp(14),0,0);wizardBody.addView(next);
        if(wizardPage>0)addH(next,button("Back",false,()->{wizardPage--;wizardStep();}),1,0);
        else addH(next,button("Later",false,()->wizard.dismiss()),1,0);
        addH(next,button(wizardPage==3?"Finish":"Next",true,()->{
            if(wizardPage==3){deck.prefs.edit().putBoolean("setup",true).apply();wizard.dismiss();}
            else {wizardPage++;wizardStep();}
        }),1,8);
    }
    private void wizardCheck(boolean update){
        wizardStatus=update?"Checking for an official yt-dlp update…":"Checking versions…";wizardStep();
        deck.tools(update,(msg,ok)->{wizardStatus=msg;if(wizard!=null&&wizard.isShowing()&&wizardPage==2)wizardStep();});
    }
    private void message(String name,String msg){new AlertDialog.Builder(this).setTitle(name).setMessage(msg==null?"The operation could not be completed.":msg).setPositiveButton("OK",null).show();}
    private void openUri(String url,String error){try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(url)));}catch(Exception e){message("Open link",error);}}
    private Dialog dialog(String name,LinearLayout inner){
        Dialog d=new Dialog(this);d.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout frame=new LinearLayout(this){
            @Override protected void onMeasure(int w,int h){
                int cap=Math.min(dp(655),getResources().getDisplayMetrics().heightPixels-dp(75));
                int available=MeasureSpec.getMode(h)==MeasureSpec.UNSPECIFIED?cap:Math.min(cap,MeasureSpec.getSize(h));
                super.onMeasure(w,MeasureSpec.makeMeasureSpec(Math.max(dp(100),available),MeasureSpec.AT_MOST));
            }
        };
        frame.setOrientation(LinearLayout.VERTICAL);frame.setBackground(box(0xff0e2028,0xff47636a,14));
        TextView bar=title(name,25);bar.setPadding(dp(16),dp(12),dp(16),dp(7));frame.addView(bar);
        ScrollView s=new ScrollView(this);s.setFillViewport(false);s.addView(inner);frame.addView(s,new LinearLayout.LayoutParams(-1,-2));
        d.setContentView(frame);return d;
    }
    private void size(Dialog d){
        Window w=d.getWindow();if(w==null)return;
        w.setBackgroundDrawableResource(android.R.color.transparent);w.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
        w.setDimAmount(.69f);w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        w.setLayout(Math.min(dp(530),getResources().getDisplayMetrics().widthPixels-dp(28)),WindowManager.LayoutParams.WRAP_CONTENT);
    }
    private void volume(LinearLayout b,String title,String key,int value){
        TextView name=label(title+" · "+value+"%",13,TEAL);addTop(b,name,5);
        SeekBar bar=new SeekBar(this);bar.setProgressTintList(ColorStateList.valueOf(GOLD));bar.setThumbTintList(ColorStateList.valueOf(GOLD));bar.setMax(100);bar.setProgress(value);bar.setContentDescription(title);b.addView(bar);
        bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            @Override public void onProgressChanged(SeekBar x,int value,boolean fromUser){if(fromUser){name.setText(title+" · "+value+"%");deck.prefs.edit().putInt(key,value).apply();deck.audio.preferences();}}
            @Override public void onStartTrackingTouch(SeekBar x){}
            @Override public void onStopTrackingTouch(SeekBar x){}
        });
    }
    private LinearLayout dialogBody(){LinearLayout v=vertical();v.setPadding(dp(16),dp(9),dp(16),dp(17));return v;}
    private LinearLayout panel(){LinearLayout v=vertical();v.setBackground(box(PANEL,LINE,12));v.setPadding(dp(14),dp(13),dp(14),dp(14));return v;}
    private LinearLayout vertical(){LinearLayout v=new LinearLayout(this);v.setOrientation(LinearLayout.VERTICAL);return v;}
    private LinearLayout horizontal(){LinearLayout v=new LinearLayout(this);v.setOrientation(LinearLayout.HORIZONTAL);return v;}
    private int dp(float d){return Math.round(d*getResources().getDisplayMetrics().density);}
    private TextView label(String value,int sp,int color){TextView v=new TextView(this);v.setText(value);v.setTextColor(color);v.setTextSize(sp);v.setLineSpacing(dp(2),1);return v;}
    private TextView kicker(String s){TextView v=label(s,11,GOLD);v.setTypeface(Typeface.MONOSPACE,Typeface.BOLD);v.setLetterSpacing(.08f);return v;}
    private TextView title(String s,int pt){TextView v=label(s,pt,PALE);v.setTypeface(Typeface.create("serif",Typeface.NORMAL));v.setPadding(0,dp(1),0,dp(4));return v;}
    private void caption(LinearLayout box,String s){TextView v=label(s,14,PALE);v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(0,dp(8),0,dp(4));box.addView(v);}
    private EditText entry(String hint){
        EditText v=new EditText(this);v.setHint(hint);v.setTextColor(PALE);v.setHintTextColor(MUTED);v.setTextSize(14);v.setBackground(box(0xff0a1a21,LINE,7));v.setPadding(dp(10),dp(9),dp(10),dp(9));return v;
    }
    private Spinner spin(String... strings){
        Spinner v=new Spinner(this,Spinner.MODE_DROPDOWN);v.setPadding(dp(8),0,dp(8),0);v.setBackground(box(0xff0a1a21,LINE,7));
        v.setPopupBackgroundDrawable(box(0xff152a32,LINE,6));
        ArrayAdapter<String> list=new ArrayAdapter<String>(this,android.R.layout.simple_spinner_dropdown_item,strings){
            @Override public View getView(int p,View item,ViewGroup group){TextView text=label(getItem(p)+"   ⌄",14,PALE);text.setGravity(Gravity.CENTER_VERTICAL);text.setMinHeight(dp(44));return text;}
            @Override public View getDropDownView(int p,View item,ViewGroup group){TextView text=label(getItem(p),14,PALE);text.setPadding(dp(9),0,dp(9),0);text.setGravity(Gravity.CENTER_VERTICAL);text.setMinHeight(dp(44));return text;}
        };v.setAdapter(list);return v;
    }
    private CheckBox check(String s,boolean checked){
        CheckBox v=new CheckBox(this);v.setText(s);v.setTextColor(PALE);v.setTextSize(13);v.setMinHeight(dp(44));v.setMinWidth(0);v.setChecked(checked);
        v.setButtonTintList(new ColorStateList(new int[][]{new int[]{android.R.attr.state_checked},new int[]{}},new int[]{GOLD,MUTED}));
        return v;
    }
    private Button button(String name,boolean primary,Runnable action){
        Button v=new Button(this);v.setAllCaps(false);v.setText(name);v.setTextSize(13);v.setMinWidth(0);v.setMinimumWidth(0);v.setMinHeight(dp(44));v.setPadding(dp(9),dp(4),dp(9),dp(4));v.setLetterSpacing(0);
        v.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},new int[]{0xff829798,primary?0xff1c1710:PALE}));
        v.setBackground(new android.graphics.drawable.RippleDrawable(ColorStateList.valueOf(0x35f6d89d),box(primary?0xffe6b876:0xff152a32,primary?0xfff4cc91:LINE,7),null));v.setOnClickListener(w->action.run());return v;
    }
    private GradientDrawable box(int fill,int line,int radius){GradientDrawable g=new GradientDrawable();g.setColor(fill);g.setCornerRadius(dp(radius));g.setStroke(dp(1),line);return g;}
    private void addH(LinearLayout b,View child,int weight,int gap){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(weight>0?0:-2,dp(44),weight);p.leftMargin=dp(gap);b.addView(child,p);}
    private void addTop(LinearLayout b,View child,int gap){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.topMargin=dp(gap);b.addView(child,p);}
    private static void setChanged(TextView view,String value){if(!TextUtils.equals(view.getText(),value))view.setText(value);}
    private static int safeIndex(int i,int count){return Math.max(0,Math.min(count-1,i));}
    private static String host(String url){try{return Access.link(url).getHost();}catch(Exception e){return "Source";}}
}
