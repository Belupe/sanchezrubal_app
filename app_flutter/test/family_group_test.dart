// Fija el contrato entre FamilyGroup.fromMap y Profile.fromMap.
//
// Los dos modelos hablan de lo mismo desde extremos opuestos: `familyGroups()`
// pide los grupos con sus miembros anidados, y `allProfiles()` pide los perfiles
// con su pertenencia anidada. Profile.fromMap solo entiende la segunda forma, así
// que FamilyGroup.fromMap tiene que rearmarla.
//
// Cuando dejó de hacerlo, nada falló: el papel llegaba nulo y la ficha del grupo
// pintaba a todo el mundo como "Miembro" aunque en la base de datos estuviera
// bien guardado. Un cambio de permiso se guardaba, la pantalla recargaba y
// volvía a salir "Miembro", así que parecía que no se guardaba nada.
import 'package:flutter_test/flutter_test.dart';
import 'package:portal_familia/models/family_group.dart';
import 'package:portal_familia/models/profile.dart';

void main() {
  // Tal cual lo devuelve PostgREST para la consulta de DataService.familyGroups():
  //   select id, name, color, owner_id,
  //          group_members(group_id, role, profiles(id, name, email, role))
  Map<String, dynamic> respuestaDelServidor() => {
        'id': 'g1',
        'name': 'Sanchez Bas',
        'color': '#3b82f6',
        'owner_id': null,
        'group_members': [
          {
            'group_id': 'g1',
            'role': 'FAMILY_ADMIN',
            'profiles': {
              'id': 'u1',
              'name': 'Pedro',
              'email': 'pedro@ejemplo.com',
              'role': 'USER',
            },
          },
          {
            'group_id': 'g1',
            'role': 'FAMILY_SECOND_ADMIN',
            'profiles': {
              'id': 'u2',
              'name': 'Marian',
              'email': 'marian@ejemplo.com',
              'role': 'USER',
            },
          },
        ],
      };

  test('el papel dentro de la casa sobrevive al aplanado', () {
    final grupo = FamilyGroup.fromMap(respuestaDelServidor());
    final pedro = grupo.members.firstWhere((m) => m.id == 'u1');
    final marian = grupo.members.firstWhere((m) => m.id == 'u2');

    expect(pedro.groupRole, 'FAMILY_ADMIN');
    expect(marian.groupRole, 'FAMILY_SECOND_ADMIN');

    // Es lo que se ve en pantalla: el desplegable de permiso y la etiqueta.
    expect(pedro.groupRoleLabel, 'Administrador familiar');
    expect(marian.groupRoleLabel, 'Administrador secundario');
  });

  test('el rango global no se contamina con el papel de la casa', () {
    final grupo = FamilyGroup.fromMap(respuestaDelServidor());
    final pedro = grupo.members.firstWhere((m) => m.id == 'u1');

    // Son ortogonales desde la migración 0025: administrar tu casa no te hace
    // administrador de la aplicación.
    expect(pedro.role, 'USER');
    expect(pedro.isPrincipal, isFalse);
    expect(pedro.isGroupAdmin, isTrue);
    expect(pedro.familyGroupId, 'g1');
  });

  test('un grupo sin miembros no revienta', () {
    final grupo = FamilyGroup.fromMap({
      'id': 'g2',
      'name': 'Vacío',
      'color': '#000000',
      'group_members': <dynamic>[],
    });
    expect(grupo.members, isEmpty);
  });

  // La otra mitad del contrato: la forma que Profile.fromMap recibe de verdad
  // cuando la consulta va al revés (DataService.allProfiles()).
  test('Profile.fromMap lee la pertenencia anidada', () {
    final p = Profile.fromMap({
      'id': 'u1',
      'name': 'Pedro',
      'email': 'pedro@ejemplo.com',
      'role': 'USER',
      'group_members': [
        {'group_id': 'g1', 'role': 'FAMILY_ADMIN'},
      ],
    });
    expect(p.groupRole, 'FAMILY_ADMIN');
    expect(p.familyGroupId, 'g1');
  });

  test('sin pertenencia, el papel es nulo y no se hereda del rango global', () {
    final p = Profile.fromMap({
      'id': 'u3',
      'name': 'Suelto',
      'role': 'USER',
      'group_members': <dynamic>[],
    });
    expect(p.groupRole, isNull);
    expect(p.familyGroupId, isNull);
  });
}
