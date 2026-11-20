import '../../../core/model/key_value.dart';
import '../../../core/util/ids.dart';
import '../../environments/domain/variables.dart';
import '../../requests/domain/request_models.dart';
import '../../testing/domain/assertions.dart';
import 'collections_cubit.dart';

/// Display names for the sample requests, so they can be localized by the UI.
class SampleNames {
  const SampleNames({
    required this.collection,
    required this.get,
    required this.post,
    required this.bearer,
    required this.notFound,
    required this.folder,
    required this.uuid,
    required this.echo,
  });

  final String collection;
  final String get;
  final String post;
  final String bearer;
  final String notFound;
  final String folder;
  final String uuid;
  final String echo;
}

/// Creates a small collection of ready-to-send requests against httpbin.org.
/// The requests only run when the user sends them. Returns the collection id.
Future<String> createSampleCollection(
  CollectionsCubit cubit,
  SampleNames n,
) async {
  final col = await cubit.createCollection(n.collection);
  await cubit.updateCollection(
    col.copyWith(
      description: 'https://httpbin.org',
      variables: <Variable>[
        Variable(id: newId(), key: 'base_url', value: 'https://httpbin.org'),
      ],
    ),
  );

  Assertion status(String code) =>
      Assertion(id: newId(), kind: AssertionKind.statusEquals, expected: code);

  Future<void> save(RequestModel r, {String? parentId}) =>
      cubit.saveRequest(request: r, collectionId: col.id, parentId: parentId);

  await save(
    RequestModel(
      id: newId(),
      name: n.get,
      url: '{{base_url}}/get',
      params: const <KeyValue>[KeyValue(key: 'hello', value: 'world')],
      assertions: <Assertion>[status('200')],
    ),
  );
  await save(
    RequestModel(
      id: newId(),
      name: n.post,
      method: 'POST',
      url: '{{base_url}}/post',
      bodyType: BodyType.json,
      body: '{\n  "name": "PostBox",\n  "local_first": true\n}',
      assertions: <Assertion>[
        status('200'),
        Assertion(
          id: newId(),
          kind: AssertionKind.jsonPathEquals,
          target: r'$.json.name',
          expected: 'PostBox',
        ),
      ],
    ),
  );
  await save(
    RequestModel(
      id: newId(),
      name: n.bearer,
      url: '{{base_url}}/bearer',
      auth: const AuthConfig(type: AuthType.bearer, token: 'demo-token'),
      assertions: <Assertion>[status('200')],
    ),
  );
  await save(
    RequestModel(
      id: newId(),
      name: n.notFound,
      url: '{{base_url}}/status/404',
      assertions: <Assertion>[status('404')],
    ),
  );

  final folder = await cubit.createFolder(col.id, null, n.folder);
  await save(
    RequestModel(
      id: newId(),
      name: n.uuid,
      url: '{{base_url}}/uuid',
      extractions: <Extraction>[
        Extraction(
          id: newId(),
          variable: 'uuid',
          source: ExtractionSource.jsonPath,
          expression: r'$.uuid',
        ),
      ],
    ),
    parentId: folder.id,
  );
  await save(
    RequestModel(
      id: newId(),
      name: n.echo,
      method: 'POST',
      url: '{{base_url}}/anything',
      bodyType: BodyType.json,
      body: '{\n  "id": "{{uuid}}"\n}',
      assertions: <Assertion>[
        Assertion(
          id: newId(),
          kind: AssertionKind.statusEquals,
          expected: '200',
        ),
      ],
    ),
    parentId: folder.id,
  );
  return col.id;
}
