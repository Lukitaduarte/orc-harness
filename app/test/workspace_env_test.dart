import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/model.dart';

void main() {
  test("a workspace's envs stay in it", () {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["work","home"]}');
    d.handle(
      '{"type":"workspaces","workspaces":['
      '{"id":"trabalho","name":"Trabalho","accounts":["work"],"memory":null,"budget_usd":null},'
      '{"id":"casa","name":"Casa","accounts":["home"],"memory":null,"budget_usd":null}]}',
    );
    d.handle(
      '{"type":"catalog","entries":['
      '{"id":"env-SHARED","kind":"env","name":"SHARED","has_value":true},'
      '{"id":"env-casa-GH_TOKEN","kind":"env","name":"GH_TOKEN","has_value":true,"workspace":"casa"},'
      '{"id":"env-trabalho-GH_TOKEN","kind":"env","name":"GH_TOKEN","has_value":true,"workspace":"trabalho"}],"templates":[]}',
    );
    store.selectWorkspace('trabalho');
    final envs = store.profileItems
        .where((i) => i.kind == CatalogKind.env)
        .map((i) => i.id);
    expect(envs, ['env-SHARED', 'env-trabalho-GH_TOKEN']);

    // A new env here: owned by this workspace, value stored for it.
    store.addCatalogItem(
      CatalogKind.env,
      'NPM_TOKEN',
      '',
      '',
      secretValue: 'x',
      onlyThisWorkspace: true,
    );
    final upsert = sent.firstWhere((m) => m['type'] == 'upsert_catalog');
    expect((upsert['entry'] as Map)['workspace'], 'trabalho');
    expect((upsert['entry'] as Map)['id'], 'env-trabalho-npm-token');
    expect(sent.last, {
      'type': 'set_secret',
      'name': 'NPM_TOKEN',
      'value': 'x',
      'workspace': 'trabalho',
    });

    // Removing an owned env deletes that workspace's value only.
    store.removeCatalogItem(
      store.catalog.firstWhere((i) => i.id == 'env-casa-GH_TOKEN'),
    );
    expect(sent.last, {
      'type': 'delete_secret',
      'name': 'GH_TOKEN',
      'workspace': 'casa',
    });
    store.dispose();
    d.dispose();
  });
}
