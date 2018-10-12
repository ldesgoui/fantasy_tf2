begin;

insert into tournament
    values ( 'i63'
           , 'i63'
           , now()
           , now() + interval '2 week'
           , 13000
           , 10
           );

COPY real_team (tournament, name) FROM stdin;
i63	Se7en
i63	FAINT Gaming
i63	Ascent.EU
i63	SVIFT
i63	The Bus Crew
i63	Ora Elektro
i63	Timed Out
i63	froyotech
\.

COPY player (tournament, player_id, name, real_team, main_class, price) FROM stdin;
i63	[U:1:10403381]	b4nny	froyotech	scout	30000
i63	[U:1:93699014]	arekk	froyotech	scout	29000
i63	[U:1:84024852]	yomps	froyotech	soldier	27000
i63	[U:1:52105383]	Garbuglio	froyotech	soldier	21500
i63	[U:1:93355936]	Habib	froyotech	demoman	29000
i63	[U:1:84193779]	Cookiejake	froyotech	medic	29000
i63	[U:1:141929391]	Counou	FAINT Gaming	scout	22000
i63	[U:1:69312244]	Sorex	FAINT Gaming	scout	21000
i63	[U:1:173260346]	Amarok	FAINT Gaming	soldier	22000
i63	[U:1:73618776]	Samski	FAINT Gaming	soldier	14000
i63	[U:1:80717784]	Alle	FAINT Gaming	demoman	25000
i63	[U:1:346440795]	Seeds	FAINT Gaming	medic	23000
i63	[U:1:95046319]	Olgha	Ascent.EU	scout	20000
i63	[U:1:31892934]	Opti	Ascent.EU	scout	17500
i63	[U:1:116488376]	Raf	Ascent.EU	soldier	16000
i63	[U:1:83489966]	Corbac	Ascent.EU	soldier	15000
i63	[U:1:117926946]	Elacour	Ascent.EU	demoman	24000
i63	[U:1:54738661]	Ombrack	Ascent.EU	medic	16000
i63	[U:1:52863028]	SMZI	SVIFT	scout	25000
i63	[U:1:118795990]	Funs	SVIFT	scout	25000
i63	[U:1:115047039]	Papi	SVIFT	soldier	23000
i63	[U:1:109457536]	Chris	SVIFT	soldier	16000
i63	[U:1:63291043]	Smirre	SVIFT	demoman	27000
i63	[U:1:106786225]	Connor	SVIFT	medic	25000
i63	[U:1:97928150]	alba	The Bus Crew	scout	18000
i63	[U:1:46032762]	Deox	The Bus Crew	scout	17000
i63	[U:1:63821331]	Poison	The Bus Crew	soldier	18000
i63	[U:1:27351209]	Tobs	The Bus Crew	soldier	11500
i63	[U:1:89086738]	Yohn	The Bus Crew	demoman	18000
i63	[U:1:74608787]	Marten	The Bus Crew	medic	18000
i63	[U:1:103786523]	Thalash	Se7en	scout	30000
i63	[U:1:115334142]	Thaigrr	Se7en	scout	29000
i63	[U:1:124355652]	AMS	Se7en	soldier	25000
i63	[U:1:88908480]	Adysky	Se7en	soldier	21000
i63	[U:1:3048631]	Kaidus	Se7en	demoman	26000
i63	[U:1:47737701]	Starkie	Se7en	medic	29000
i63	[U:1:73130293]	Nevo	Ora Elektro	scout	21000
i63	[U:1:171355038]	Scruff	Ora Elektro	scout	19000
i63	[U:1:51856748]	Azunis	Ora Elektro	soldier	18000
i63	[U:1:98556886]	iatgink	Ora Elektro	soldier	13000
i63	[U:1:87585084]	Eemes	Ora Elektro	demoman	20000
i63	[U:1:102629081]	Demos	Ora Elektro	medic	18000
i63	[U:1:39136524]	Maros	Timed Out	scout	19000
i63	[U:1:195922481]	Toemas	Timed Out	scout	16000
i63	[U:1:97885288]	PolygoN	Timed Out	soldier	16500
i63	[U:1:185199867]	matthes	Timed Out	soldier	12000
i63	[U:1:165445936]	NasBoii	Timed Out	demoman	16000
i63	[U:1:99996681]	BaBs	Timed Out	medic	14000
\.

insert into manager select generate_series, generate_series from generate_series(1, 1000);
insert into team select 'i63', generate_series, generate_series, 140000 from generate_series(1, 1000);
insert into contract (tournament, manager, player, time, purchase_price, sale_price)
   select 'i63'
        , generate_series
        , player_id
        , tsrange(now()::timestamp, (now() + interval '1 hour')::timestamp)
        , price
        , price + 200
     from generate_series(1, 1000),
  lateral (select * from player order by random() limit 6) j;

insert into contract (tournament, manager, player, time, purchase_price)
   select 'i63'
        , generate_series
        , player_id
        , tsrange((now() + interval '1 hour')::timestamp, null)
        , price
     from generate_series(1, 1000),
  lateral (select * from player order by random() limit 6) j;

insert into match values (0, 'i63', null, 0);
insert into match values (1, 'i63', null, 0, now() + interval '2 hours');
insert into map values ('0', 0);
insert into map values ('1', 1);
insert into performance
    select '0'
         , 'i63'
         , player_id
         , generate_series
         , ((random() * 30)::int)::float
      from player,
   lateral generate_series(1, 30);
insert into performance
    select '1'
         , 'i63'
         , player_id
         , generate_series
         , ((random() * 30)::int)::float
      from player,
   lateral generate_series(1, 30);

insert into multiplier values ('i63', '1', 1);
insert into multiplier values ('i63', '2', 10);
insert into multiplier values ('i63', '3', -2);
insert into multiplier values ('i63', '4', 1);
insert into multiplier values ('i63', '5', 10);
insert into multiplier values ('i63', '6', -2);

refresh materialized view contract_view;
refresh materialized view private.team_view_helper;

commit;
