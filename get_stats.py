#!/usr/bin/env python3

from collections import defaultdict
from contextlib import suppress
from bs4 import BeautifulSoup
from pprint import pprint
import cfscrape
import requests


# TODO: Heals/Min


def emit(player, stat, value):
    #print(f"{player:20} {stat:30} {value}")
    print(stat)


ESEA_STATS = [
        'damage',
        'damage per minute',
        'kills',
        None,
        'assists',
        None,
        'deaths',
        None,
        'heals received',
        'medic kills',
        'point captures',
        None,
        None,
        None,
        'ubercharges used',
        'ubercharges dropped',
    ]


def esea(match_id):
    page = cfscrape.create_scraper().get(f"https://play.esea.net/match/{match_id}").text
    soup = BeautifulSoup(page, 'html.parser')

    team_stats = { 1: { 'total heals': 0 }, 2: { 'total heals': 0 } }
    player_stats = {}

    score_1, score_2 = soup.select('#stats-match-view > section.match-header > h1')[0].text.split()[-1].split('-')

    team_stats[1]['map won'] = int(score_1 > score_2)
    team_stats[1]['map lost'] = int(score_1 < score_2)
    team_stats[1]['rounds won'] = score_1
    team_stats[1]['rounds lost'] = score_2
    team_stats[2]['map won'] = int(score_2 > score_1)
    team_stats[2]['map lost'] = int(score_2 < score_1)
    team_stats[2]['rounds won'] = score_2
    team_stats[2]['rounds lost'] = score_1

    def process_row(player_row, team):
        player_id = player_row.select('a[href^=/users]')[0]['href'][7:].strip()

        stats = dict(zip(ESEA_STATS, (float(v.text.strip()) for v in player_row.select('.stat'))))
        del stats[None]

        stats['team'] = team
        stats['kills per death'] = stats['kills'] / max(stats['deaths'], 1)
        stats['kills and assists per death'] = (stats['kills'] + stats['assists']) / max(stats['deaths'], 1)
        stats['damage per death'] = stats['damage'] / max(stats['deaths'], 1)
        if stats['ubercharges used'] or stats['ubercharges dropped']:
            stats['kills as medic'] = stats['kills']
            team_stats[team]['team medic deaths'] = stats['deaths']
        else:
            team_stats[team]['total heals'] += stats['heals received']

        player_stats[player_id] = stats

    for player_row in soup.select('#body-match-total1 tr'):
        process_row(player_row, 1)

    for player_row in soup.select('#body-match-total2 tr'):
        process_row(player_row, 2)

    highest_kills = max(player_stats.values(), key=lambda d: d['kills'])
    highest_kills_per_death = max(player_stats.values(), key=lambda d: d['kills per death'])
    highest_damage = max(player_stats.values(), key=lambda d: d['damage'])

    for p, d in player_stats.items():
        for key, value in team_stats[d['team']].items():
            if key != 'total heals':
                emit(p, key, value)

        for key, value in d.items():
            if key != 'team':
                emit(p, key, value)

        if d['ubercharges used'] or d['ubercharges dropped']:
            emit(p, 'heals given', team_stats[d['team']]['total heals'])

        emit(p, 'highest kills', int(d['kills'] == highest_kills))
        emit(p, 'highest damage', int(d['damage'] == highest_damage))
        emit(p, 'highest kills per death', int(d['kills per death'] == highest_kills_per_death))


def logs(log_id):
    data = requests.get(f"http://logs.tf/json/{log_id}").json()

    highest_kills = max(data['players'].values(), key=lambda d: d['kills'])
    highest_kills_per_death = max(data['players'].values(), key=lambda d: d['kpd'])
    highest_damage = max(data['players'].values(), key=lambda d: d['dmg'])

    team_stats = { 'Red': {}, 'Blue': {} }
    red = data['teams']['Red']
    blue = data['teams']['Red']

    team_stats["Red"]['map won'] = int(red['score'] > blue['score'])
    team_stats["Red"]['map lost'] = int(red['score'] < blue['score'])
    team_stats["Blue"]['map won'] = int(red['score'] < blue['score'])
    team_stats["Blue"]['map lost'] = int(red['score'] > blue['score'])
    team_stats["Red"]['rounds won'] = red['score']
    team_stats["Red"]['rounds lost'] = blue['score']
    team_stats["Blue"]['rounds won'] = blue['score']
    team_stats["Blue"]['rounds lost'] = red['score']
    team_stats["Red"]['team medic deaths'] = sum(
        v.get('medic', 0)
        for k, v in data['classkills'].items()
        if data['players'][k]['team'] == 'Blue'
    )
    team_stats["Blue"]['team medic deaths'] = sum(
        v.get('medic', 0)
        for k, v in data['classkills'].items()
        if data['players'][k]['team'] == 'Red'
    )

    for p, d in data['players'].items():
        for key, value in team_stats[d['team']].items():
            emit(p, key, value)

        emit(p, 'airshots', d['as'])
        emit(p, 'assists', d['assists'])
        emit(p, 'backstabs', d['backstabs'])
        emit(p, 'damage per death', d['dapd'])
        emit(p, 'damage per minute', d['dapm'])
        emit(p, 'damage taken', d['dt'])
        emit(p, 'damage', d['dmg'])
        emit(p, 'deaths', d['deaths'])
        emit(p, 'headshot kills', d['headshots'])
        emit(p, 'headshots', d['headshots_hit'])
        emit(p, 'heals given', d['heal'])
        emit(p, 'heals received from medkits', d['medkits_hp'])
        emit(p, 'heals received', d['hr'])
        emit(p, 'kills and assists per death', d['kapd'])
        emit(p, 'kills per death', d['kpd'])
        emit(p, 'kills', d['kills'])
        emit(p, 'longest kill streak', d['lks'])
        emit(p, 'medkits picked up', d['medkits'])
        emit(p, 'point captures', d['cpc'])
        emit(p, 'sentries built', d['sentries'])
        emit(p, 'suicides', d['suicides'])
        emit(p, 'ubercharges dropped', d['drops'])
        emit(p, 'ubercharges used', d['ubers'])

        emit(p, 'highest kills', int(d['kills'] == highest_kills))
        emit(p, 'highest damage', int(d['dmg'] == highest_damage))
        emit(p, 'highest kills per death', int(d['kpd'] == highest_kills_per_death))

        emit(p, 'kills as medic', sum(c['kills'] for c in d['class_stats'] if c['type'] == "medic"))

        emit(p, 'medic kills', data['classkills'][p].get('medic', 0))

esea(13918450)
logs(2122126)
