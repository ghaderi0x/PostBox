import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/app/services.dart';
import 'package:postbox/features/collections/application/collections_cubit.dart';
import 'package:postbox/features/collections/application/sample_data.dart';
import 'package:postbox/features/requests/domain/request_models.dart';

void main() {
  test('sample collection has a variable, a folder and six requests with tests', () async {
    final services = AppServices.inMemory();
    final cubit = CollectionsCubit(services.collections, services.vault);
    addTearDown(cubit.close);
    await cubit.load();

    final id = await createSampleCollection(
      cubit,
      const SampleNames(
        collection: 'Samples',
        get: 'Get',
        post: 'Post',
        bearer: 'Bearer',
        notFound: 'NotFound',
        folder: 'Chain',
        uuid: 'Uuid',
        echo: 'Echo',
      ),
    );

    final col = cubit.state.collection(id)!;
    expect(col.name, 'Samples');
    expect(col.variables.single.key, 'base_url');

    final nodes = cubit.state.nodes;
    expect(nodes.where((n) => n.isFolder).length, 1);
    final requests = nodes.where((n) => !n.isFolder).toList();
    expect(requests.length, 6);
    expect(requests.every((n) => n.request!.url.startsWith('{{base_url}}')), isTrue);
    expect(requests.every((n) => n.request!.assertions.isNotEmpty || n.request!.extractions.isNotEmpty), isTrue);

    // The bearer sample keeps its demo token in the keystore, not in the database.
    final bearer = requests.firstWhere((n) => n.name == 'Bearer');
    final raw = services.database.db.select('SELECT data_json FROM nodes WHERE id = ?', <Object?>[bearer.id]).first['data_json'] as String;
    expect(raw.contains('demo-token'), isFalse);
    final full = await cubit.loadFullRequest(bearer);
    expect(full.auth.type, AuthType.bearer);
    expect(full.auth.token, 'demo-token');
  });
}
