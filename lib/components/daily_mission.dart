/// One daily mission: reach [target] and claim [reward] coins. Progress is
/// tracked by the game (see SubwayGame.missionProgress) and everything
/// resets automatically the first time the app is opened on a new day.
class MissionDef {
  final String id;
  final String title;
  final int target;
  final int reward;

  const MissionDef(this.id, this.title, this.target, this.reward);
}

const List<MissionDef> kDailyMissions = [
  MissionDef('coins', 'Collect 200 coins', 200, 50),
  MissionDef('hops', 'Hop on 5 trains', 5, 50),
  MissionDef('score', 'Score 60 in one run', 60, 75),
];